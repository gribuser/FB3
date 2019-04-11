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

my $DefaultChars = 2000;

my ($Help, $Force, $In, $Out, $CutChars, $XsdPath, $ImagesPath, $ImageFileName, $WorkType);
my $r = GetOptions(
  'help|h'         => \$Help,
	'force|f'	       =>	\$Force,
	'in|i=s'		     =>	\$In,
	'out|o=s'		     =>	\$Out,
	'chars|c=i'	     =>	\$CutChars,
	'xsd|x=s'        => \$XsdPath, # optional
  'imagespath|p=s' => \$ImagesPath,
	'type|t=s'       => \$WorkType,
);
help() if $Help;

if (!$In || !$Out) {
  print "\nrequired params 'in'/'out' not defined\n";
  help();
}

$CutChars = $DefaultChars unless $CutChars;

if($ImagesPath){
  die "Path $ImagesPath not found\n" unless -d $ImagesPath;
  $ImagesPath = $ImagesPath.'/' if $ImagesPath !~ /\/$/;
}

if ($WorkType && $WorkType !~ /^(trial|output)$/) {
  print "\nparams 'type' must be trial|output\n";
	help();
}
$WorkType = 'trial' unless $WorkType; 

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
my %HrefHash;
my %IdHash;
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

if ($WorkType eq 'trial') {
	$RootNode = ProceedNodeTrial($RootNode);
} elsif ($WorkType eq 'output') {
	$RootNode = ProceedNodeOut($RootNode);
	CollectElementStat($RootNode);
	CleanLinks($FB3Body);
} else {die "type wrong!"; help();}

CleanImages($FB3Package);

$BodyDoc->toFile($FB3Body->PhysicalName, 0);

if ($WorkType eq 'trial') {
	my $CharsFull = length($RootNode->textContent);
	my $CharsTrial = length($RootNode->textContent);

	my $FB3Descr = $FB3Package->Meta;
	my $DescrXML = $FB3Descr->Content;
	my $DescrDoc = $Parser->load_xml( string => $DescrXML, huge => 1 );
	my $DescrNode = $DescrDoc->getDocumentElement();
	my $FB3FragmentNode = $DescrDoc->createElement('fb3-fragment');
	$FB3FragmentNode->setAttribute('full_length', $CharsFull);
	$FB3FragmentNode->setAttribute('fragment_length', $CharsTrial);
	$DescrNode->appendChild($FB3FragmentNode);
	$DescrDoc->toFile($FB3Descr->PhysicalName, 0);
}

die "Empty body in result file" unless scalar @{$XPC->findnodes("/fb:fb3-body/fb:section",$RootNode)};

ZipFolder("$FB3TmpDir/", $Out);
if( my $ValidationError = $Validator->Validate( $Out )) {
	unless ($Force) {
		unlink $Out;
		die "Validation error:  $ValidationError";
	}
}

sub CollectElementStat {
	my $Node = shift || return;
	#быстрее, чем //xpath
	for my $ChildNode ($Node->childNodes) {
		next if $ChildNode->nodeName eq '#text';
		CollectElementStat($ChildNode);
		$ImageHash{$ChildNode->getAttribute('src')} = 1 if $ChildNode->nodeName eq 'img';
		if (my $Id = $ChildNode->getAttribute('id')) {
      $IdHash{$Id} = 1;
		}
		if ($ChildNode->nodeName eq 'a') {
			if (my $Href = $ChildNode->getAttribute('xlink:href')) {
      	if ($Href =~ s/^#//) {
					$HrefHash{$Href} = 1;
				} 
			}
		}
	}
}

sub ProceedNodeOut {
	my $Node = shift || return;

	#актуален только первый уровень section
	for my $ChildNode ($Node->childNodes) {
		next unless $ChildNode->nodeName eq 'section';
		my $Output = $ChildNode->getAttribute('output');
		if ($Output eq 'trial-only') {
			$ChildNode->unbindNode();
		}
	}	

	return $Node;
}

sub ProceedNodeTrial {
	my $Node = shift || return;
	my $ImmortalBranch = shift || 0; # не убивать потомков

	my $NodeName = $Node->nodeName;
	if ($NodeName eq '#text') {
		$CharsProcessed += length($Node->nodeValue);
		$Node->unbindNode() if ($Finish && !$ImmortalBranch);
		return;
	}

	if ($NodeName eq 'section') {

		if ( #обрабатываем логику атрибута 'output'
			defined $Node->getAttribute('output')	
			&& $Node->parentNode->nodeName ne 'section' #только внешние section
		) {
			my $SectionOutput = $Node->getAttribute('output');
			if ($SectionOutput eq 'payed') { #пропускаем ноду и забываем
				$Node->unbindNode();
				return $Node;
			}
			if ($SectionOutput eq 'trial' || $SectionOutput eq 'trial-only') { #всегда бессмертны
				$ImmortalBranch = 1;
			}
		}

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
		$ChildNode = ProceedNodeTrial($ChildNode, $ImmortalBranch);
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

	if ($Finish && !$ImmortalBranch && (!$Node->firstChild || Trim(InNode($Node)) eq '') ) {
		$Node->unbindNode(); # если нет потомков - рубим.
	}

	return $Node;
}

sub InNode {
  my $Node = shift;
  join "",map {$_->toString} $Node->childNodes;
}

sub Trim {
	my $Str = shift;
	$Str =~ s/[\n\r]//g;
	$Str =~ s/^\s+//g;
	$Str =~ s/\s+$//g;
	return $Str;
}

sub NReplace {
	my $Node = shift;
	my $Parent = $Node->parentNode();
	my $Clone = $BodyDoc->createElement($Parent->nodeName());
	foreach ($Parent->getAttributes) {
		$Clone->setAttribute($_->nodeName => $_->value);
	}
	foreach my $PNode ($Parent->childNodes()) {
		if ($PNode == $Node) {
			foreach ($PNode->childNodes) {
				$Clone->appendChild($_);
			}
			next;
		}
		$Clone->appendChild($PNode);
	}
	$Parent->replaceNode($Clone);
}

sub CleanLinks {
	my $FB3Body = shift;

	foreach my $Id (keys %IdHash) {
		next if exists $HrefHash{$Id};
		my $Ids = $XPC->findnodes('//*[@id="'.$Id.'"]');
		foreach my $NodeIds (@$Ids) {
			next if $NodeIds->nodeName() eq 'section';
			if ($NodeIds->nodeName eq 'span') {
				NReplace($NodeIds);
			} else {
				$NodeIds->removeAttribute('id');
			}
		}
		delete $IdHash{$Id};
	}

	foreach my $Href (keys %HrefHash) {
		next if exists $IdHash{$Href};
		print $Href."\n";
		my $Hrefs = $XPC->findnodes('//fb:a[@xlink:href="#'.$Href.'"]');
		foreach my $NodeHrefs (@$Hrefs) {
			if ($NodeHrefs->getAttribute('id')) {
				$NodeHrefs->removeAttribute('xlink:href');
				next;
			}
			NReplace($NodeHrefs);
		}
		delete $HrefHash{$Href};
	}

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

sub help {
  print qq{
  USAGE: cutfb3.pl --in=<input.file> --out=<output.file> [options]
  
  --chars|c     : chars in result for trial file. default $DefaultChars
  --imagespath  : =/path/to/fb3/images
  --type|t      : type of work (trial|output) default 'trial'
  --help|h      : print this text

};
exit;
}


1;
