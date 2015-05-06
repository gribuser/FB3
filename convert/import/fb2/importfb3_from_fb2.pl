#!/usr/bin/perl
use strict;
use Getopt::Long;
use File::Temp;
use File::Copy;
use File::Basename;
use XML::LibXML;
use XML::LibXSLT;
use MIME::Base64;
use Cwd qw(cwd abs_path getcwd);

#
#   command line parser code
#

my ($help, $verbose, $script_dir);
$script_dir = dirname(__FILE__);

GetOptions(
  'help|h'        =>  \$help,
  'verbose|v'     =>  \$verbose
) or usage ("Incorrect usage!");

usage() if (defined $help);
usage() if (@ARGV < 2);
usage(qq{File "$ARGV[0]" doesn't exist or empty!}) unless ( -e $ARGV[0] );

sub usage {
  my $message = $_[0];
  if (defined $message && length $message) {
    $message .= "\n" unless $message =~ /\n$/;
  }
  
  my $command = $0;
  $command =~ s#^.*/##;
   
  print STDERR (
    $message,
    qq{usage: $command [options] <input.fb2> <output.fb3> 
       --help -h       => this help
       --verbose -v    => debug messages}
  );

  die("\n")
}

#
#   main code routine
#
##################################################################

my @TransformConfig = (
  {stylesheet => "/body.xsl", output => "/fb3/body.xml"},
  {stylesheet => "/description.xsl", output => "/fb3/description.xml"},
  {stylesheet => "/body_rels.xsl", output => "/fb3/_rels/body.xml.rels"},
  {stylesheet => "/core.xsl", output => "/fb3/meta/core.xml"}
);

my $Parser = XML::LibXML->new;
my $XPC = XML::LibXML::XPathContext->new;
my $XSLT = XML::LibXSLT->new;
$XPC->registerNs('fb', 'http://www.gribuser.ru/xml/fictionbook/2.0');

#prepare
my $TmpDir = File::Temp->newdir;
my $TmpFB3 = File::Temp->new;
foreach ("/fb3", "/fb3/img", "/fb3/img", "/fb3/meta", "/fb3/_rels", "/_rels"){
  mkdir "$TmpDir$_";
}
print "Directory structure is created successfully.\n" if $verbose;

#transform
for (@TransformConfig) {
  my $Stylesheet = $XSLT->parse_stylesheet_file("$script_dir$_->{stylesheet}");
  my $Results = $Stylesheet->transform_file($ARGV[0]);
  $Stylesheet->output_file($Results, "$TmpDir$_->{output}");
}
print "XML transformation has been successful.\n" if $verbose;

#extract images
my $XML = $Parser->parse_file($ARGV[0]);

my ($CoverNode)=$XPC->findnodes('/fb:FictionBook/fb:description/fb:title-info/fb:coverpage/fb:image[1]',$XML);
my $CoverID;
if ($CoverNode){
  $CoverID=lc($CoverNode->getAttribute('l:href'));
  $CoverID=~s/^#//;
}

for ($XPC->findnodes('/fb:FictionBook/fb:binary',$XML))
{
  my $id=$_->getAttribute('id');
  print "Image converted: '$id'\n" if $verbose;
  my $ContentType=$_->getAttribute('content-type');

  if (defined($id) && $ContentType=~ /image\/(jpeg|png)/i)
  {
    my $FN="$TmpDir/fb3/img/".lc($id);
    open IMGFILE, ">$FN" or die "$FN: $!";
    binmode IMGFILE;
    print (IMGFILE decode_base64($_->string_value()));
    close IMGFILE;

  } elsif (defined($id) && $ContentType=~ /image\/gif/i) {
    $!=18;
    die "GIF image found!";
  } elsif (defined($id) && $ContentType){
    $!=18;
    die "Unknown type '$ContentType' binary found!";
  }
}
print "Cover image found: $CoverID.\n" if $verbose;
print "Pictures extracted successfully.\n" if $verbose;

#compile required files
my $FN="$TmpDir/[Content_Types].xml";
open FH, ">$FN" or die "$FN: $!";
print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
	<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
	<Default Extension="png" ContentType="image/png"/>
	<Default Extension="jpg" ContentType="image/jpeg"/>
	<Default Extension="gif" ContentType="image/gif"/>
	<Default Extension="svg" ContentType="image/svg+xml"/>
	<Default Extension="xml" ContentType="application/xml"/>

	<Override PartName="/fb3/meta/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>

	<Override PartName="/fb3/description.xml" ContentType="application/fb3-description+xml"/>
	<Override PartName="/fb3/body.xml" ContentType="application/fb3-body+xml"/>
</Types>
EOF
close FH;

my $FN="$TmpDir/_rels/.rels";
open FH, ">$FN" or die "$FN: $!";
print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
	<Relationship Id="rId0" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="fb3/img/$CoverID"/>
	<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="fb3/meta/core.xml"/>
	<Relationship Id="rId2" Type="http://www.fictionbook.org/FictionBook3/relationships/Book" Target="fb3/description.xml"/>
</Relationships>
EOF
close FH;
print "Reference files successfully created.\n" if $verbose;


#zip
my $TmpZipFN = $TmpFB3->filename . ".zip";
ZipFolder ("$TmpDir/", $TmpZipFN);

#validation
unless (ValidateFB3( $TmpZipFN )){
  die 'FB3 validate error';
}
print "FB3 file validated successfully.\n" if $verbose;

#publish fb3
move($TmpZipFN, $ARGV[1]) or die "The move operation failed: $!";
print "FB3 file created successfully.\n" if $verbose;

##################################################################

#FB3 validator
sub ValidateFB3{
  my $FileName = shift;

	#validate zip
  my $fn_abs = abs_path ("$FileName");
	my $cmd="zip -T $fn_abs";
	my $CmdResult=`$cmd`;
	print $CmdResult if $verbose;
	return 0 unless ($CmdResult =~ /OK/);

  #validate OK
	return 1;
}

sub ZipFolder{
  my $SourceFileName=shift;
	my $TargetFileName=shift;
  my @first = @_;

  open FH,">$TargetFileName";
  close FH;
  my $fn_abs = abs_path ("$TargetFileName");
	unlink "$TargetFileName";

  my $old_dir = cwd();
  chdir "$SourceFileName";
	my $cmd="zip -Xr9Dq $fn_abs ".join(' ',@first)." *";
	my $CmdResult=`$cmd`;
	warn $CmdResult if $CmdResult;
  chdir $old_dir if $old_dir;
}
