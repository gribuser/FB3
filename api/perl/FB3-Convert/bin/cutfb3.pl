#!/usr/local/bin/perl
use strict;

use XML::LibXML;
use OPC::Node;
use FB3;
use FB3::Validator;
use File::Copy;
use File::Temp;
use File::Basename qw(basename);
use Cwd qw(cwd abs_path);
use Getopt::Long;
use utf8;

my ($Force, $In, $Out, $CutChars, $XsdPath, $ImagesPath, $ImageFileName);
GetOptions(
	'force|f'	  =>	\$Force,
	'in|i=s'		=>	\$In,
	'out|o=s'		=>	\$Out,
	'chars|c=i'	=>	\$CutChars,
	'xsd|x=s'   =>  \$XsdPath, # optional
  'imagespath|p=s'  =>  \$ImagesPath,
) or usage ("CutPartFB3: makes trial fragment from fb3\n\nUsage:\n\nCutPartFB3.pl in=<inputfile.fb3> out=<outputfile.fb3> chars=<chars_in_result> imagespath=/path/to/fb3/images\n");

if($ImagesPath){
  die "Path $ImagesPath not found\n" unless -d $ImagesPath;
  $ImagesPath = $ImagesPath.'/' if $ImagesPath !~ /\/$/;
}

use constant {
	NS_XLINK => 'http://www.w3.org/1999/xlink',
	NS_FB3_DESCRIPTION => 'http://www.fictionbook.org/FictionBook3/description',
	NS_FB3_BODY => 'http://www.fictionbook.org/FictionBook3/body'
};

my $Blocks = qr/^(p|subtitle|ol|ul|pre|table|poem|blockquote|div|subscription)$/;

use constant {
	RELATION_TYPE_FB3_BOOK =>
		'http://www.fictionbook.org/FictionBook3/relationships/Book',
	RELATION_TYPE_FB3_BODY =>
		'http://www.fictionbook.org/FictionBook3/relationships/body',
	RELATION_TYPE_OPC_THUMBNAIL =>
		'http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail',
	RELATION_TYPE_CORE_PROP =>
		'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
	RELATION_TYPE_FB3_IMAGES =>
		'http://www.fictionbook.org/FictionBook3/relationships/image',
};

our $Validator = FB3::Validator->new( $XsdPath );

my $Finish;
my $CharsProcessed = 0;
my %ImageHash;
my %NoteHash;

my $TmpDir = File::Temp::tempdir( CLEANUP => 1 );
my $FB3TmpDir = $TmpDir.'/unzipped_'.File::Basename::basename($In);
my $UnzipMessage = `/usr/bin/unzip -o -d $FB3TmpDir $In 2>&1`;
die "Unzipping fb3 error: $UnzipMessage" if $?;

my $FB3Package = FB3->new( from_dir => $FB3TmpDir );
my $FB3Body = $FB3Package->Body;
my $BodyXML = $FB3Body->Content;
my $Parser = XML::LibXML->new();
my $BodyDoc = $Parser->load_xml( string => $BodyXML, huge => 1 );
my $RootNode = $BodyDoc->getDocumentElement();
my $XPC = XML::LibXML::XPathContext->new($RootNode);
$XPC->registerNs('fb', &NS_FB3_BODY);
my $CharsFull = length($RootNode->textContent);
$RootNode = ProceedNode($RootNode);
CleanImages($FB3Package);
my $CharsTrial = length($RootNode->textContent);
$BodyDoc->toFile($FB3Body->PhysicalName, 0);

my $FB3Descr = $FB3Package->Meta;
my $DescrXML = $FB3Descr->Content;
my $DescrDoc = $Parser->load_xml( string => $DescrXML, huge => 1 );
my $DescrNode = $DescrDoc->getDocumentElement();
my $FB3FragmentNode = $DescrDoc->createElement('fb3-fragment');
$FB3FragmentNode->setAttribute('full_length', $CharsFull);
$FB3FragmentNode->setAttribute('fragment_length', $CharsTrial);
$DescrNode->appendChild($FB3FragmentNode);
$DescrDoc->toFile($FB3Descr->PhysicalName, 0);

ZipFolder ("$FB3TmpDir/", $Out);
if( my $ValidationError = $Validator->Validate( $Out )) {
	unless ($Force) {
		unlink $Out;
		die "Validation error:  $ValidationError";
	}
}

sub ProceedNode {
	my $Node = shift || return;
	my $ImmortalBranch = shift || 0; # не убивать потомков

	my $NodeName = $Node->nodeName;
	if ($NodeName eq '#text') {
		$CharsProcessed += length($Node->nodeValue);
		$Node->unbindNode() if ($Finish && !$ImmortalBranch);
		return;
	}

	if ($NodeName eq 'section') {
		$Node->setAttribute('first-char-pos', $CharsProcessed+1);
	} elsif ($NodeName eq 'title' && ($Node->parentNode->nodeName eq 'section' || $Node->parentNode->nodeName eq 'notes')) { # заголовок секции, пригодится
		$ImmortalBranch = 1;
	} elsif ($NodeName eq 'img' && (!$Finish || $ImmortalBranch)) {
		$ImageHash{$Node->getAttribute('src')} = 1;
	} elsif ($NodeName eq 'note') {
		my $NoteHref = $Node->getAttribute('href');
		$NoteHash{$NoteHref} = 1 if (!$Finish || $ImmortalBranch);
	} elsif ($NodeName eq 'notebody') {
		if (!$NoteHash{$Node->getAttribute('id')}) {
			$Node->unbindNode();
		} else {
			$ImmortalBranch = 1;
		}
	}
	for my $ChildNode ($Node->childNodes) {
		if ($ChildNode->nodeName =~ /$Blocks/) {
			unless (($CharsProcessed + length($ChildNode->textContent)) < $CutChars) {
				$Finish = 1;
			}
		}
		$ChildNode = ProceedNode($ChildNode, $ImmortalBranch);
	}

	if ($NodeName eq 'section') {
		my @SectionChildren = $Node->nonBlankChildNodes;
		$Node->setAttribute('clipped', 'true') if $Finish;
		if (scalar @SectionChildren == 0 || (scalar @SectionChildren == 1 && $SectionChildren[0]->nodeName eq 'title')
				|| (scalar @SectionChildren == 2 && $SectionChildren[0]->nodeName eq 'title' && ($SectionChildren[1]->nodeName eq 'epigraph' || $SectionChildren[1]->nodeName eq 'annotation'))
		) { # проверка, что в секции нет ничего кроме заголовка
			$SectionChildren[1]->unbindNode() if ($SectionChildren[1] && ($SectionChildren[1]->nodeName eq 'epigraph' || $SectionChildren[1]->nodeName eq 'annotation'));
			my $ClippedNode = XML::LibXML::Element->new('clipped');
			$Node->appendChild($ClippedNode);
		}
	}

	if($NodeName eq 'image'){
      $ImageFileName = $Node->getAttribute('href');
      $ImageFileName =~ s/^#//;
      # Если нет, то игнорируем, потому что мы уже получили триал и теперь уже работаем с ним
      if(-f $ImagesPath.$ImageFileName){
        my ($x, $y) = imgsize($ImagesPath.$ImageFileName);
        if($x && $y && $x >= 100 && $y >= 100){
          $CharsProcessed += 200;
        }
      }
  }

	if ($NodeName eq 'notes') {
		my @NotesChildren = $Node->nonBlankChildNodes;
		if (scalar @NotesChildren == 0 || (scalar @NotesChildren == 1 && $NotesChildren[0]->nodeName eq 'title')
				|| (scalar @NotesChildren == 2 && $NotesChildren[0]->nodeName eq 'title' && $NotesChildren[1]->nodeName eq 'epigraph')) {
			$Node->unbindNode();
		}
	}

	if ($Finish && !$ImmortalBranch && !$Node->firstChild) {
		$Node->unbindNode(); # если нет потомков - рубим.
	}

	return $Node;
}

sub CleanImages {
	my $FB3 = shift;
  my $FB3Body = $FB3->Body;

	my %TrialImageFiles;
	my @FilePathes;

	# иногда так случается, что в исходном FB3 нет обложки
	my $cover = eval { $FB3->Cover->PhysicalName };
	# следующая строка чтобы не удалить обложку
	$TrialImageFiles{$cover} = 1 if $cover;

	my @ImagesAll = $FB3Body->Relations(type => RELATION_TYPE_FB3_IMAGES);
	foreach (@ImagesAll) { # эта картинка сохранилась в триалке
		my $NewPart = $FB3->Part( $_->{TargetFullName} );
		my $FullPath = $NewPart->PhysicalName;
		push (@FilePathes, $FullPath);
		if ($ImageHash{$_->{Id}}) {
			$TrialImageFiles{$FullPath} = 1; # Нужный файлик, запомним.
		} else {
			$FB3Body->RemoveRelations( id => $_->{Id} );
		}
	}

	foreach (@FilePathes) {
		unlink $_ unless $TrialImageFiles{$_};
	}

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

1;
