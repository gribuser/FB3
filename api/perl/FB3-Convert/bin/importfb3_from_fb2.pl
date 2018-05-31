#!/usr/local/bin/perl
use strict;
use utf8;
use open qw(:std :utf8);
use Getopt::Long;
use File::Temp;
use File::Copy;
use XML::LibXML;
use XML::LibXSLT;
use MIME::Base64;
use Cwd qw(cwd abs_path getcwd);
use Encode 'decode_utf8';
use FB3::Validator;
use File::ShareDir qw/dist_dir/;

#
#   command line parser code
#

my ($help, $verbose, $script_dir, $force_create_fb3, $print_validation_errors, $xsd_dir,
	$CustomMetaPath);

$script_dir = dist_dir('FB3-Convert');

GetOptions(
	'help|h'											=>	\$help,
	'verbose|v'										=>	\$verbose,
	'force|f'											=>	\$force_create_fb3,
	'print-validation-errors|p'		=>	\$print_validation_errors,
	'xsd=s'												=>	\$xsd_dir,
	'meta=s'											=>	\$CustomMetaPath,
) or usage ("Incorrect usage!");

usage() if (defined $help);
usage() if (@ARGV < 2);
usage(qq{File "$ARGV[0]" doesn't exist or empty!}) unless ( -e $ARGV[0] );
usage(qq{--xsd option is required!}) unless $xsd_dir;

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
       --help -h                    => this help
       --verbose -v                 => debug messages
       --force -f                   => force create fb3 file (ignore validation result)
       --print-validation-error -p  => print validation errors
       --xsd="path"                 => path to directory with FB3 xsd files (see https://github.com/gribuser/FB3)
       --meta="path"                => path to custom FB3 meta file (otherwise it would be generated from FB2)}
  );

  die("\n")
}

#
#   main code routine
#
##################################################################

my @TransformConfig = (
  {stylesheet => "/body.xsl", output => "/fb3/body.xml"},
  {stylesheet => "/body_rels.xsl", output => "/fb3/_rels/body.xml.rels"},
  {stylesheet => "/core.xsl", output => "/fb3/meta/core.xml"}
);

unless( $CustomMetaPath ) {
	# no meta file was given, so need to generate meta from FB2
	push @TransformConfig,
		{stylesheet => "/description.xsl", output => "/fb3/description.xml"};
}

my $FB2Doc = XML::LibXML->load_xml( location => $ARGV[0] );
$FB2Doc->setEncoding('utf-8');

my $XPC = XML::LibXML::XPathContext->new;
my $XSLT = XML::LibXSLT->new;
$XPC->registerNs('fb', 'http://www.gribuser.ru/xml/fictionbook/2.0');
my $TmpDir = File::Temp->newdir;

#fix FB2 with regular expression checks (what XLST 1.0 can't do itself)
my $IsValidUUIDRegEx = qr/^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$/;
my( $FB2IdNode ) = $XPC->findnodes(
	'/fb:FictionBook/fb:description/fb:document-info/fb:id/text()', $FB2Doc );
if( $FB2IdNode && $FB2IdNode->data !~ $IsValidUUIDRegEx ) {
	$FB2IdNode->setData( '00000000-0000-0000-0000-000000000000' );
}
for my $PersonNode ( $XPC->findnodes(
		'/fb:FictionBook/fb:description/fb:title-info/fb:author
		| /fb:FictionBook/fb:description/fb:title-info/fb:translator', $FB2Doc )) {

	my( $IdTextNode ) = $XPC->findnodes( 'fb:id/text()', $PersonNode );
	if( $IdTextNode && $IdTextNode->data !~ $IsValidUUIDRegEx ) {
		$IdTextNode->setData( '00000000-0000-0000-0000-000000000000' );
	}
}
my( $PublishInfoNode ) =
	$XPC->findnodes( '/fb:FictionBook/fb:description/fb:publish-info', $FB2Doc );
if( $PublishInfoNode ) {
	my $IsValidISBNRegEx = qr/([0-9]+[\-\s]){3,6}[0-9]*[xX0-9]/;
	for my $ISBNNode ( $XPC->findnodes( 'fb:isbn', $PublishInfoNode )) {
		my $ISBN = $ISBNNode->textContent;
		unless( $ISBN =~ /^$IsValidISBNRegEx$/ ) {
			my $FixedISBN;
			if( $ISBN =~ /^[0-9]{10,13}$/ ) {
				# this is ISBN without separators. Need just to prettify it
				if( length( $ISBN ) == 10 ) {
					# ISBN 10, format it as 5-699-15000-5
					$FixedISBN = substr($ISBN,0,1).'-'.substr($ISBN,1,3).'-'.substr($ISBN,4,5).
						'-'.substr($ISBN,9);
				} else {
					# ISBN 13, format it as 978-5-17-084861-4
					$FixedISBN = substr($ISBN,0,3).'-'.substr($ISBN,3,1).'-'.substr($ISBN,4,2).
						'-'.substr($ISBN,6,6).'-'.substr($ISBN,12);
				}
			} elsif( $ISBN =~ /($IsValidISBNRegEx)/ ) {
				# Whole ISBN is invalid, but it contains valid ISBN inside
				$FixedISBN = $1;
			}
			if( $FixedISBN ) {
				my( $ISBNTextNode ) = $XPC->findnodes( 'text()', $ISBNNode );
				$ISBNTextNode->setData( $FixedISBN );
			} else {
				# this is completely corrupted ISBN, throw it away
				$PublishInfoNode->removeChild( $ISBNNode );
				#warn "Removed ISBN '$ISBN' as it's not matching pattern for valid ISBNs in FB3";
			}
		}
	}
}

# корректируем заголовок сноски: берём текст между фигурными/квадратными скобками
my $AutoNoteNumber = 0;
for my $note ( $XPC->findnodes('//fb:a[@type="note"]', $FB2Doc) ) {
  if ( my $text = [ $note->findnodes('./text()') ]->[0] ) {
        $text->setData($1) if ( $text->data =~ /\[(\w+)\]/ or $text->data =~ /\{(\w+)\}/ );
  }
  else {
    # если в заголовке сноски нет ничего, формируем самостоятельно
    $note->appendTextNode('#' . ++$AutoNoteNumber);
  }
}

# Особо сложные эпиграфы порубим на куски тут. TODO полностью перенести работу с эпиграфами сюда.
for my $Cite ( $XPC->findnodes('//fb:epigraph/fb:cite[1]', $FB2Doc )) {
	my @SetInEpigraph;
	for my $Sibling ( $XPC->findnodes('following-sibling::*', $Cite)) { # всё что после первого cite выделяем в отдельный эпиграф
		push @SetInEpigraph, $Sibling;
		if ($Sibling->nodeName eq 'cite') {
			CreateEpigraph($Cite->parentNode, @SetInEpigraph);
			@SetInEpigraph = ();
		}
	}
	CreateEpigraph($Cite->parentNode, @SetInEpigraph); # сбросим хвост
}

sub CreateEpigraph {
	my $Epigraph = shift;
	my @SetInEpigraph = @_;
	return unless scalar @SetInEpigraph;

	my $NewEpigraph = $FB2Doc->createElement('epigraph');
	$Epigraph->parentNode->insertAfter($NewEpigraph, $Epigraph);
	foreach (@SetInEpigraph) {
		$Epigraph->removeChild($_);
		$NewEpigraph->appendChild($_);
	}

	return $NewEpigraph;
}

# Работаем с картинками, которые нужно выделить в div или section
for my $ImgNode ( $XPC->findnodes('//fb:section[ancestor::fb:body[not(@name="notes")]]/fb:image', $FB2Doc )) {
	# Ищем подпись. Все <p> до <empty-line/>, но не более 300 символов.
	my @SubscrNodes;
	my $ImgSubscrLength;
	# удалим пустые строки до картинки. Этот кусок можно в будущем использовать для нахождения подписи до картинки
	my @NodesForDelete;
	my $PrevSibling = $ImgNode;
	while ($PrevSibling = $PrevSibling->previousSibling()) {
		if ($PrevSibling->nodeName eq 'empty-line') {
			push @NodesForDelete, $PrevSibling;
		} else {
			last;
		}
	}
	foreach (@NodesForDelete) {
		$_->unbindNode();
	}
	# найдем подпись и удалим пустые строки после картинки
	my $EmptyLineFound = 0;
	for my $Sibling ( $XPC->findnodes('following-sibling::*', $ImgNode )) {
		if ($ImgSubscrLength <= 300) {
			my $SiblingName = $Sibling->nodeName;
			if ($SiblingName eq 'p' && !$EmptyLineFound) {
				$ImgSubscrLength += length($Sibling->textContent);
				push @SubscrNodes, $Sibling;
			} elsif ($SiblingName eq 'empty-line') {
				$Sibling->unbindNode();
				$EmptyLineFound = 1;
			} else {
				@SubscrNodes = () unless $EmptyLineFound;
				last;
			}
		} else {
			@SubscrNodes = ();
			last;
		}
	}

	# Перенесем подпись и картинку куда положено
	# Переносим картинку
	my $ParentNode = $ImgNode->parentNode;
	my $PNode = $FB2Doc->createElement('p');
	my $NextSibling = $ImgNode->nextNonBlankSibling();
	my $NewParentNode;
	if ($XPC->exists('following-sibling::fb:section', $ImgNode)) {
		$NewParentNode = $FB2Doc->createElement('section');
	} else {
		$NewParentNode = $FB2Doc->createElement('div');
		$NewParentNode->setAttribute('float', 'center');
		$NewParentNode->setAttribute('on-one-page', '1');
	}
	$ParentNode->insertBefore($NewParentNode, $ImgNode);
	$NewParentNode->appendChild($PNode);
	$PNode->appendChild($ImgNode);
	#Переносим подпись
	foreach (@SubscrNodes) {
		$NewParentNode->appendChild($_);
	}
}

my $TmpFB2File = "$TmpDir/book.fb2";
open my $fh, '>', $TmpFB2File
	or die "Could not open $TmpFB2File for writing";
print $fh decode_utf8($FB2Doc->toString);
close $fh;

#prepare directory structure for FB3
my $TmpFB3 = File::Temp->new;
foreach ("/fb3", "/fb3/img", "/fb3/style", "/fb3/meta", "/fb3/_rels", "/_rels"){
  mkdir "$TmpDir$_";
}
print "Directory structure is created successfully.\n" if $verbose;

#transform
for (@TransformConfig) {
  my $Stylesheet = $XSLT->parse_stylesheet_file($script_dir.$_->{stylesheet});
  my $Results = $Stylesheet->transform_file( $TmpFB2File );
  $Stylesheet->output_file($Results, $TmpDir.$_->{output});
}
unlink $TmpFB2File; # удаляем за ненадобностью
print "XML transformation has been successful.\n" if $verbose;

#place custom fb3 meta if it was given
if( $CustomMetaPath ) {
	File::Copy::copy $CustomMetaPath, "$TmpDir/fb3/description.xml"
		or die "can't copy custom meta '$CustomMetaPath' to fb3: $!";
}

#extract images
my ($CoverNode)=$XPC->findnodes('/fb:FictionBook/fb:description/fb:title-info/fb:coverpage/fb:image[1]',$FB2Doc);
my $CoverID;
if ($CoverNode){
  $CoverID=lc($CoverNode->getAttribute('l:href'));
  $CoverID=~s/^#//;
}

my $ImagesFound = 0;
for ($XPC->findnodes('/fb:FictionBook/fb:binary',$FB2Doc)) {
  $ImagesFound = 1;

  my $id=$_->getAttribute('id');
  print "Converting image '$id'...\n" if $verbose;
  my $ContentType=$_->getAttribute('content-type');

  if (defined($id) && $ContentType=~ /image\/(jpeg|png)/i) {
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
print "Cover image found: $CoverID.\n" if $verbose && $CoverID;
print "Pictures extracted successfully.\n" if $verbose && $ImagesFound;

#extract stylesheets
my $SheetCount = 0;
for my $SheetNode ( $XPC->findnodes( '/fb:FictionBook/fb:stylesheet', $FB2Doc )) {
  $SheetCount++;

  print "Converting #$SheetCount stylesheet...\n" if $verbose;

  my $ContentType = $SheetNode->getAttribute('type');
  unless( $ContentType eq 'text/css' ) {
    $!=18;
    die "Can convert only text/css stylesheets, but received a $ContentType";
  }

  my $FN="$TmpDir/fb3/style/style$SheetCount.css";
  open FH, ">", $FN
    or die "$FN: $!";
  print FH $SheetNode->string_value;
  close FH;
}
print "Stylesheets extracted successfully.\n" if $verbose && $SheetCount > 0;

#compile required files
my $FN="$TmpDir/[Content_Types].xml";
open FH, ">$FN" or die "$FN: $!";
print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
	<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
	<Default Extension="png" ContentType="image/png"/>
	<Default Extension="jpg" ContentType="image/jpeg"/>
	<Default Extension="jpeg" ContentType="image/jpeg"/>
	<Default Extension="gif" ContentType="image/gif"/>
	<Default Extension="svg" ContentType="image/svg+xml"/>
	<Default Extension="xml" ContentType="application/xml"/>
	<Default Extension="css" ContentType="text/css"/>

	<Override PartName="/fb3/meta/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>

	<Override PartName="/fb3/description.xml" ContentType="application/fb3-description+xml"/>
	<Override PartName="/fb3/body.xml" ContentType="application/fb3-body+xml"/>
</Types>
EOF
close FH;

my $FN="$TmpDir/_rels/.rels";
open FH, ">$FN" or die "$FN: $!";
print FH qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
	}.( $CoverID ? qq{<Relationship Id="rId0" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="fb3/img/$CoverID"/>} : '' ).qq{
	<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="fb3/meta/core.xml"/>
	<Relationship Id="rId2" Type="http://www.fictionbook.org/FictionBook3/relationships/Book" Target="fb3/description.xml"/>
</Relationships>};
close FH;

my $FN="$TmpDir/fb3/_rels/description.xml.rels";
open FH, ">$FN" or die "$FN: $!";
print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
	<Relationship Id="rId0"
		Target="body.xml"
		Type="http://www.fictionbook.org/FictionBook3/relationships/body" />
</Relationships>
EOF
close FH;
print "Reference files successfully created.\n" if $verbose;


#zip
my $TmpZipFN = $TmpFB3->filename . ".zip";
ZipFolder ("$TmpDir/", $TmpZipFN);

#validation
unless ( ValidateFB3( $TmpZipFN ) ){
	die 'FB3 validate error' unless $force_create_fb3;
	print "FB3 file validated with errors.\n" if $verbose;
} else {
	print "FB3 file validated successfully.\n" if $verbose;
}

#publish fb3
move($TmpZipFN, $ARGV[1]) or die "The move operation failed: $!";
print "FB3 file created successfully.\n" if $verbose;

##################################################################

#FB3 validator
sub ValidateFB3{
	my $FileName = shift;

	#validate just zip
	my $fn_abs = abs_path ("$FileName");
	my $cmd="zip -T $fn_abs";
	my $CmdResult=`$cmd`;
	print $CmdResult if $verbose;
	return 0 unless ($CmdResult =~ /OK/);

	#check all
	my $Validator = FB3::Validator->new( $xsd_dir );
	my $ValidationError = $Validator->Validate( $FileName );
	print "$ARGV[0] to FB3 conversion is not valid: $ValidationError" if $ValidationError && $print_validation_errors;
	return 0 if $ValidationError;
	
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
