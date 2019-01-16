#!/usr/local/bin/perl
use strict;

use XML::LibXML;
use OPC::Node;
use FB3;
use utf8;
use Encode;
use open qw(:std :utf8);
use Image::Info;
use JSON::Path;
use JSON::PP;
use File::Copy;
use File::Basename;
use MIME::Base64;

use Getopt::Long;

my $FB3     = '';
my $Out     = '';
my $Version = '1.0';
my $Lang    = 'en';
my $ArtID   = undef;

GetOptions ('in|from|src|fb3=s' => \$FB3,
            'out|to|dst|json=s' => \$Out,
            'lang=s'            => \$Lang,
            'art|art-id=s'      => \$ArtID,
            'version=s'         => \$Version) or print join('', <DATA>) and die("Error in command line arguments\n");

print join('', <DATA>) and die "ERROR: source directory not specified, use --fb3 parameter\n"       unless $FB3;
print join('', <DATA>) and die "ERROR: destination directory not specified, use --json parameter\n" unless $Out;

die "\nERROR: source directory `$FB3' not found\n"      unless -d $FB3;
die "\nERROR: destination directory `$Out' not found\n" unless -d $Out;

$Out = $Out.'/' unless $Out =~ /\/$/;

unless ($Version =~ /^\d+\.\d+$/) {
	$Version = ($Version =~ /^\d+$/) ? "1.$Version" : "1.0"
}

my $PartLimit = 20000;
my $IsTrial   = 0;

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

use constant {
	NS_XLINK => 'http://www.w3.org/1999/xlink',
	NS_FB3_DESCRIPTION => 'http://www.fictionbook.org/FictionBook3/description',
	NS_FB3_BODY => 'http://www.fictionbook.org/FictionBook3/body'
};

my %AttrHash = (
	'article'        => 'artc',
	'float'          => 'fl',
	'align'          => 'aln',
	'valign'         => 'valn',
	'bindto'         => 'bnd',
	'border'         => 'brd',
	'on-one-page'    => 'op',
	'colspan'        => 'csp',
	'rowspan'        => 'rsp',
	'class'          => 'nc',
	'autotext'       => 'att',
	'page-before'    => 'pb',
	'page-after'     => 'pa',
	'width'          => 'wth',
	'min-width'      => 'minw',
	'max-width'      => 'maxw',
	'clipped'        => 'cl',
	'first-char-pos' => 'fcp',
);

my %LangDependentStr = (
	'ru' => ['Конец ознакомительного фрагмента'],
	'uk' => ['Кінець ознайомчого фрагмента'],
	'en' => ['End of fragment'],
	'de' => ['Ende des Fragments'],
	'fr' => ['Fin du fragment'],
	'az' => ['Fragmanın sonu'],
	'be' => ['Канец азнаямленчага фрагмента'],
	'bn' => ['ফ্র্যাগমেন্ট সম্পূর্ণ হয়েছে'],
	'bg' => ['Край на фрагмента'],
	'el' => ['Τέλος του θραύσματος'],
	'ka' => ['ფრაგმენტის დასასრული'],
	'da' => ['Fragmentet afsluttet'],
	'es' => ['Fin del fragmento'],
	'it' => ['Fine del frammento'],
	'kk' => ['Фрагменттің соңы'],
	'ca' => ['Fi del fragment'],
	'ky' => ['Сот жазманын'],
	'zn' => ['片段結束'],
	'ko' => ['프래그먼트의 끝'],
	'la' => ['Finis iudicii fragmentum'],
	'lv' => ['Fragments beigas'],
	'lt' => ['Fragmento pabaiga'],
	'mk' => ['Крајот на фрагментот'],
	'no' => ['Slutten av fragmentet'],
	'pl' => ['Koniec fragmentu'],
	#'pt' => ['Koniec fragmentu'],
	'ro' => ['Sfârșitul fragmentului'],
	'sr' => ['Фрагмент завршен'],
	'sk' => ['Konec fragmenta'],
	'fi' => ['Fragmentin loppu'],
	'hbs' => ['Kraj fragmenta'],
	'cs' => ['Konec fragmentu'],
	'sv' => ['Fragmentet slutfört'],
	'eo' => ['Fino de fragmento'],
	'et' => ['Fragment lõpp'],
	'ja' => ['断片の終わり'],
	'nl' => ['Einde fragment'],
	);

$Lang = 'en' unless $LangDependentStr{$Lang}[0];

my @AuthorsPriority = qw(author co_author dubious_author lecturer compiler screenwriter translator contributing_editor managing_editor editor editorial_board_member adapter conceptor rendering associated commentator consultant scientific_advisor recipient_of_letters corrector composer);

my $NoHyphRe = qr/^(poem|epigraph|subtitle|title)$/; # Ноды, текст которых(и их потомков) нельзя переносить
my $Semiblocks = qr/^(epigraph|annotation|poem|stanza)$/;
my $BlockPParents = qr/^(section|annotation|epigraph|notebody)$/;
my $LineBreakChars = qr/[\-\/…\?\!\}\|–—]/;
my $SubtitleParents = qr/^(section)$/;

# ------------------------ Hyphenation settings ------------------------------
use constant HYPHEN => "\x{AD}"; #visible in, e.g., Komodo Edit.

my ($hyphenPatterns, $hyphenRegexPattern, $soglasnie, $glasnie, $znaki, $RgxSoglasnie, $RgxGlasnie, $RgxZnaki, $RgxNonChar);

$hyphenPatterns = {
	GSS => 'GS' . &HYPHEN . 'S',
	SGSG => 'SG' . &HYPHEN . 'SG',
	SQS => 'SQ' . &HYPHEN . 'S',
	GG => 'G' . &HYPHEN . 'G',
	SS => 'S' . &HYPHEN . 'S'
};
$hyphenRegexPattern = join "|",keys %{$hyphenPatterns};
$hyphenRegexPattern = qr/(.*)($hyphenRegexPattern){1}(.*)/o;

$soglasnie = "bcdfghjklmnpqrstvwxzбвгджзйклмнпрстфхцчшщ";
$glasnie = "aeiouyАОУЮИЫЕЭЯЁєіїў";
$znaki = "ъь";

$RgxSoglasnie = qr/[$soglasnie]/oi;
$RgxGlasnie = qr/[$glasnie]/oi;
$RgxZnaki = qr/[$znaki]/oi;
$RgxNonChar = qr/([^$soglasnie$glasnie$znaki]+)/oi; #в скобках, чтобы оно возвращалось при сплите.
# /----------------------- Hyphenation settings ------------------------------

my $jsonC = JSON::PP->new->pretty->allow_barekey;

my $FB3Package = FB3->new( from_dir => $FB3 );
my $TOCHeader = ProceedDescr($FB3Package->Meta->Content);
my $FB3Body = $FB3Package->Body;
my @Img = $FB3Body->Relations( type => RELATION_TYPE_FB3_IMAGES );
my @ImgFiles;
for (@Img) {
	push @ImgFiles, basename($_->{'TargetFullName'});
}
my $ImgFileNum = 0; # номер файла для замены
my $ImgHash;
for my $Image (@Img) {
	$ImgHash->{$Image->{Id}}->{name} = basename($Image->{'TargetFullName'});
	unless ($ImgHash->{$Image->{Id}}->{name} =~ /^[A-Za-z0-9_\-]+\..+$/) { # Если имя файла странное - переименуем
		$ImgHash->{$Image->{Id}}->{name} =~ /(\.[^.]+)$/;
		while (grep('renamed_img_'.$ImgFileNum.$1 eq $_, @ImgFiles)) { # проверка, что такого имени файла у нас еще нет(если есть - следующий номер и т.д.)
			$ImgFileNum++;
		}
		$ImgHash->{$Image->{Id}}->{name} = 'renamed_img_'.$ImgFileNum.$1;
		$ImgFileNum++;
	}
	my $FN = $Out.$ImgHash->{$Image->{Id}}->{name};
	my $PhysicalName = $FB3Package->{opc}->PhysicalNameByPartName($Image->{'TargetFullName'});
	File::Copy::copy( $PhysicalName, $FN );
	($ImgHash->{$Image->{Id}}->{height}, $ImgHash->{$Image->{Id}}->{width}) = GetImgSize($FN);
}

ProceedBody($FB3Body->Content);

my $BlockN;
my @Parts;
sub ProceedBody {
	my $BodyXML = shift;

	$BodyXML = DecodeUtf8($BodyXML);
	$BodyXML =~ s/\r?\n\r?/ /g;
	$BodyXML =~ s/([\s>])([^\s<>]+)(<note\s+[^>]*?role="(foot|end)note"[^>]*?>[^<]{1,10}<\/note>[,\.\?"'“”«»‘’;:\)…\/]?)/$1.HypheNOBR($2,$3)/ges;
	my $Parser = XML::LibXML->new();
	my $BodyDoc = $Parser->load_xml( string => $BodyXML, huge => 1 );
	my $JsonStr;
	my $TOCStr;
	my $TotalBlocks;
	# Начинаем обход всех узлов дерева
	my $Node = $BodyDoc->getDocumentElement();
	$Node = PrepareBodyXML($Node, $BodyDoc);
	my $NodeTree = ProceedNode($Node);
	my $RootLevelTOC = DumpRootLevelTOC($NodeTree);
	$JsonStr = DumpTree($NodeTree);
	$TOCStr = '{'.$TOCHeader.'Body: ['.$RootLevelTOC.'],Parts:['.(join ",\n", @Parts).']}';
	ProceedJsonBodyPart($TOCStr, 'toc.js');
	return;
}

my %InnerRefsHash;
sub ProceedNode {
	my $Node = shift || return;
	my $ParentName = shift || undef;
	my $NoHyph = shift || 0;
	my $Xp = shift || undef;
	my $NoCut = shift;
	my $NoteType = shift;
	my $InEmptySection = shift || 0;
	my $NodeName = $Node->nodeName;

	my $NodeHash;

	if ($NoHyph || $NodeName =~ /$NoHyphRe/) {
		$NodeHash->{no_hyph} = 1;
	}

	$Xp = 1 if $NodeName eq 'fb3-body';

	if ($NodeName eq '#text') {
		my $Text = $Node->nodeValue;
		return if $Text =~ /^\s+$/;
		return unless defined $Text;
		$Text = '['.$Text.']' if $NoteType eq 'footnote';
		$Text = '{'.$Text.'}' if $NoteType eq 'endnote';
		$NodeHash->{text} = $Text;
		$NodeHash->{xp} = $Xp;
		return $NodeHash;
	}

	for my $Attr ($Node->attributes) {
		my $AttrName = $Attr->getName;
		$AttrName =~ s/^.+://; # Откусим ns
		if ($AttrName eq 'empty') {
			$NodeHash->{in_empty_section} = 1;
		} else {
			$NodeHash->{attr}->{$AttrName} = EscString($Attr->getValue);
		}
	}

	$NodeHash->{in_empty_section} = 1 if $InEmptySection;
	$NoteType = $NodeHash->{attr}->{role};

	$NodeHash->{xp} = $Xp;

	$NodeHash->{name} = $NodeName;

	my ($IsBlock, $IsRootBlock, $Printable) = AnalyseNode($Node, $NodeName, $ParentName);
	$Printable = 0 if $NodeHash->{in_empty_section};

	$NodeHash->{no_cut} = $NoCut;
	if ($Printable && !$NodeHash->{no_cut}) {
		$NodeHash->{b_id} = $BlockN || '0';
		$NoCut = 1;
		$BlockN++;
	}
	$NodeHash->{pr} = $Printable;
	$NodeHash->{rb} = $IsRootBlock;

	my @Childs;
	my $i = 1;
	for my $Child ($Node->childNodes) {
		my $ChildHash = ProceedNode($Child, $NodeName, $NodeHash->{no_hyph}, $Xp.','.$i, $NoCut, $NoteType, $NodeHash->{in_empty_section});
		next unless defined $ChildHash;
		push @Childs, $ChildHash;
		$i++;
	}
	$NodeHash->{c} = [@Childs] if scalar @Childs;

	my $Id = $Node->getAttribute('id');
	if ($Id) {
		if ($NodeHash->{pr}) {
			$InnerRefsHash{$Id} = $NodeHash->{b_id};
		} else {
			MoveRefToPrintableChild($NodeHash, $Id); # Если этот блок не отражается в json, то его первому потомку, который отражается
		}
	}

	my $Href = $NodeHash->{attr}->{href};

	if (defined $Href) {
		$Href =~ s/^\#//g;
		$NodeHash->{href} = $Href;
		delete $NodeHash->{attr}->{href};
	}

	return $NodeHash;
}

sub MoveRefToPrintableChild {
	my $NodeHash = shift;
	my $Id = shift;

	foreach (@{$NodeHash->{c}}) {
		if ($_->{pr} && $_->{b_id}) { # Потомок нам подходит
			$InnerRefsHash{$Id} = $_->{b_id};
			return 1;
		} else { # Проходим по его потомкам
			if (MoveRefToPrintableChild($_, $Id)) {
				return 1;
			}
		}
	}

}

my @ResultArr;
my ($Length, $FirstBlockN, $LastBlockN, $FirstXP, $LastXP);
my $FileN = 0;
sub DumpTree {
	my $NodeHash = shift || return;
	my $JsonStr;

	if (defined $NodeHash->{text} || $NodeHash->{pr}) {
		$FirstXP = $NodeHash->{xp} if !$FirstXP && $NodeHash->{b_id};
		$LastXP = $NodeHash->{xp} if $NodeHash->{b_id};
	}

	if (defined $NodeHash->{text}) {
		$Length += length($NodeHash->{text});
		$JsonStr = ProceedTextNode($NodeHash->{text}, $NodeHash->{no_hyph} == 1 ? 0 : 1);
		return $JsonStr;
	} elsif ($NodeHash->{pr} == 1) {
		my $AttrStr = join ( ',', map { ($AttrHash{$_} ? $AttrHash{$_} : $_).':"'.$NodeHash->{attr}->{$_}.'"' } keys %{$NodeHash->{attr}}); # Дампим все атрибуты в строку
		$AttrStr = ','.$AttrStr if $AttrStr;

		if ($NodeHash->{name} eq 'br') {
			$JsonStr = '{t:"'.$NodeHash->{name}.'"'.$AttrStr.',xp:['.$NodeHash->{xp};
		} elsif ($NodeHash->{name} eq 'img') {
			$JsonStr  = '{t:"'.$NodeHash->{name}.'"'.$AttrStr.',xp:['.$NodeHash->{xp}.'],s:"'.$ImgHash->{$NodeHash->{attr}->{src}}->{name}.'"';
			$JsonStr .= ',w:' . ($ImgHash->{$NodeHash->{attr}->{src}}->{width})  if ($ImgHash->{$NodeHash->{attr}->{src}}->{width});
			$JsonStr .= ',h:' . ($ImgHash->{$NodeHash->{attr}->{src}}->{height}) if ($ImgHash->{$NodeHash->{attr}->{src}}->{height});
			$JsonStr .= '}';
		} else {
			$JsonStr = '{t:"'.$NodeHash->{name}.'"'.$AttrStr.',xp:['.$NodeHash->{xp}.'],c:[';
		}

		$JsonStr .= "\n" if $NodeHash->{name} =~ /$Semiblocks/;
	} else {
		$JsonStr = '';
	}
	my $ChildsCount = scalar @{$NodeHash->{c}} if $NodeHash->{c};

	$FirstBlockN = $NodeHash->{b_id} unless defined $FirstBlockN;
	$LastBlockN = $NodeHash->{b_id} if $NodeHash->{b_id};

	for my $ChildHash (@{$NodeHash->{c}}) {
		$ChildsCount--;
		$JsonStr =~ s/,$/],f:/g if $ChildHash->{name} eq 'footnote'; # Лучше бы что другое придумать, но работает
		my $ChildStr .= DumpTree($ChildHash);
		if ($ChildStr) {
			$JsonStr .= $ChildStr;
			$JsonStr .= ',' if $ChildsCount && $ChildStr;
		}
	}
	$JsonStr .= "\n" if $NodeHash->{name} =~ /$Semiblocks/;

	if ( defined $NodeHash->{href}) {
		if ($InnerRefsHash{$NodeHash->{href}}) {
			$JsonStr .= '],hr:['.$InnerRefsHash{$NodeHash->{href}}.']';
		} else {
			$JsonStr .= '],href:["'.$NodeHash->{href}.'"]';
		}
	}

	$JsonStr .= ']}' if ($NodeHash->{pr} == 1 && $NodeHash->{name} ne 'img' && $NodeHash->{name} ne 'note' && $NodeHash->{name} ne 'a');
	$JsonStr .= '}' if ($NodeHash->{name} eq 'note' || $NodeHash->{name} eq 'a');

	if ($NodeHash->{pr} == 1 && !$NodeHash->{no_cut}) {
		push @ResultArr, $JsonStr;
	}

	if (($NodeHash->{b_id} && $Length > $PartLimit) || ($NodeHash->{name} eq 'fb3-body' && $Length > 0)) {
		my $ResultStr = join ",\n",@ResultArr;
		$ResultStr =~ s/,\n$//g;
		if (trim($ResultStr)) {
			$ResultStr = '['.$ResultStr.']';
			my $FileName = sprintf("%03i.js",$FileN);
			ProceedJsonBodyPart($ResultStr, $FileName);
			$FileN++;
			@ResultArr = ();
			$Length = 0;
			push @Parts, '{s:'.$FirstBlockN.',e:'.$LastBlockN.',xps:['.$FirstXP.'],xpe:['.$LastXP.'],url:"'.$FileName.'"}';
			$FirstBlockN = undef;
			$FirstXP = undef;
		}
	}

	return $JsonStr;
}

my $LastBlock;
sub DumpRootLevelTOC {
	my $NodeHash = shift || return;
	my $TOCStr;
	my @TocStrArr;

	$LastBlock = $NodeHash->{b_id} if $NodeHash->{b_id};
	if ($NodeHash->{rb}) {
		$NodeHash->{b_id} ||= $NodeHash->{c}[0]->{b_id};
		$LastBlock = $NodeHash->{b_id} if $NodeHash->{b_id};
		push @TocStrArr, 's:'.($LastBlock ? $LastBlock : '0') unless $NodeHash->{in_empty_section};

		my @Clilds;
		my $ChildsSection;
		my $Title;
		my $TotalClipped = 0;
		if ($NodeHash->{c}[0]->{name} eq 'title') {
			$Title = 't:"'.ExtractText($NodeHash->{c}[0]).'"';
		}
		for my $ChildHash (@{$NodeHash->{c}}) {
			if ($ChildHash->{name} eq 'clipped') {
				$TotalClipped = 1;
			}
			my $ChildStr = DumpRootLevelTOC($ChildHash);
			push @Clilds, $ChildStr if $ChildStr;
		}
		if (scalar @Clilds) {
			$ChildsSection = 'c:[';
			$ChildsSection .= join ",",@Clilds;
			$ChildsSection .= ']';
		}
		push @TocStrArr, 'e:'.($LastBlock ? $LastBlock : '0') unless $NodeHash->{in_empty_section};
		push @TocStrArr, $Title if $Title;
		push @TocStrArr, $AttrHash{'first-char-pos'}.':'.$NodeHash->{attr}->{'first-char-pos'} if $NodeHash->{attr}->{'first-char-pos'};
		push @TocStrArr, $AttrHash{clipped}.':"true"' if $NodeHash->{attr}->{clipped} eq 'true';
		push @TocStrArr, 'tcl:"true"' if $TotalClipped;
		push @TocStrArr, $ChildsSection if $ChildsSection;
		$TOCStr = '{';
		$TOCStr .= join ",",@TocStrArr;
		$TOCStr .= '}';
	}
	return $TOCStr;
}

sub ExtractText {
	my $NodeHash = shift || return;
	my @TextArr;

	for my $ChildHash (@{$NodeHash->{c}}) {
		push @TextArr, $ChildHash->{text} if $ChildHash->{text};
		my $Text = ExtractText($ChildHash);
		$Text = EscString($Text);
		push @TextArr, $Text if $Text;
	}

	return join ' ', @TextArr;
}

sub PrepareBodyXML {
	my $Node = shift || undef;
	my $BodyDoc = shift;

	my $FootNoteHash;
	my $xpc = XML::LibXML::XPathContext->new($Node);
	$xpc->registerNs('fbb', &NS_FB3_BODY);
	for my $Note ($xpc->findnodes('/fbb:fb3-body/fbb:notes', $Node)) {
		if ($Note->getAttribute('show') == 0) {
			for my $NoteBody ($xpc->findnodes('./fbb:notebody', $Note)) {
				$FootNoteHash->{$NoteBody->getAttribute('id')} = ($xpc->findnodes('./*', $NoteBody));
			}
			$Note->unbindNode();
		}
	}

	for my $NoteRef ($xpc->findnodes('//fbb:note')) {
		if ($NoteRef->getAttributeNS(NS_XLINK, 'role') eq 'footnote') {
			my $Id = $NoteRef->getAttribute('href');
			$NoteRef->removeAttribute('href');
			my $FootNoteNode = $NoteRef->appendChild($BodyDoc->createElement('footnote'));
			for my $N (@{$FootNoteHash->{$Id}}) {
				$FootNoteNode->appendChild($N);
			}
		}
	}

	if ($IsTrial) {
		for my $SectionNode ($xpc->findnodes('//fbb:section', $Node)) {
			if (IsEmptySection($SectionNode)) {
				$SectionNode->setAttribute('empty', 1)
			}
		}
		my $NewSectionNode = $BodyDoc->createElementNS('fbb', 'section');
		my $NewPNode = $BodyDoc->createElementNS('fbb', 'p');
		$NewPNode->appendChild($BodyDoc->createTextNode($LangDependentStr{$Lang}[0]));
		$NewSectionNode->appendChild($NewPNode);
		my $FB3BodyNode = $xpc->findnodes('fbb:fb3-body', $BodyDoc)->[0];
		$FB3BodyNode->appendChild($NewSectionNode);
	}

	return $Node;
}

sub IsEmptySection {
	my $SectionNode = shift || return;

	my $IsEmpty;
	for my $Child ($SectionNode->nonBlankChildNodes) {
		my $ChildName = $Child->nodeName;
		if ($ChildName ne 'clipped' && $ChildName ne 'title' && $ChildName ne 'section') {
			return 0;
		} elsif ($ChildName eq 'clipped') {
			return 1;
		} elsif ($ChildName eq 'section') {
			$IsEmpty = IsEmptySection($Child);
			return 0 unless $IsEmpty;
		}
	}
	return 1 if $IsEmpty;
}

sub ProceedJsonBodyPart {
	my $JsonStr = shift;
	my $FileName = shift;

	my $JData;
	eval { $JData = $jsonC->decode($JsonStr); };
	if ($@) {
		# Такой json нам не нужен
		die "$JsonStr\n===============\n$@";
		#warn "\n$FileName: $@"; # Для отладки и теста. В боевых условиях падать, если фигня получается.
	}

	open TMPOUT, ">", $Out.$FileName or die "Cannot open tmp file: `$Out.$FileName'";
	print TMPOUT $JsonStr;
	close TMPOUT;

	return $FileName;
}

sub ProceedDescr {

	my $DescrXML = shift;

	$DescrXML = DecodeUtf8($DescrXML);
	$DescrXML =~ s/\r?\n\r?/ /g;

	my @description_data = ();

	my $Parser = XML::LibXML->new();
	my $xpc = XML::LibXML::XPathContext->new($Parser->load_xml( string => $DescrXML, huge => 1 ));
	$xpc->registerNs('fbd', &NS_FB3_DESCRIPTION);

	my $UUID = ($xpc->findnodes('/fbd:fb3-description')->[0])->getAttribute('id');

	my $SimpleFields = {
		'Title'        => 'fbd:title/fbd:main',
		'Subtitle'     => 'fbd:title/fbd:sub',
		'Lang'         => 'fbd:lang',
		'Annotation'   => 'fbd:annotation',
		'Preamble'     => 'fbd:preamble',
		'Translated'   => 'fbd:translated'
	};

	for my $field ( sort keys %$SimpleFields ) {

		my $node  = $xpc->findnodes('/fbd:fb3-description/' . $SimpleFields->{$field})->[0]  || next;
		my $value = EscString($node->string_value) || next;

		push @description_data, sprintf('%s:"%s"', $field, $value);
	}

	my $description = join ',', @description_data;

	my @Sequences = ();
	my $getSequence; $getSequence = sub {

		my @sequenceNodes = @_;

		for my $sequenceNode ( @sequenceNodes ) {

			push @Sequences, '"' . EscString($xpc->findnodes('./fbd:title/fbd:main', $sequenceNode)->[0]->string_value) . '"';

			$getSequence->( $xpc->findnodes('./fbd:sequence', $sequenceNode) );
		}
	};
	$getSequence->( $xpc->findnodes('/fbd:fb3-description/fbd:sequence') );
	$description .= ',Sequences:[' . join(',', @Sequences) . ']' if scalar @Sequences;

	my $getParts = sub {

		my $node   = shift;
		my $struct = shift;

		my @values = ();

		for my $part ( keys %$struct ) {

			my $subNode = $xpc->findnodes('./fbd:' . $struct->{$part}, $node)->[0] || next;
			my $value   = EscString($subNode->string_value) || next;

			push @values, sprintf('%s:"%s"', $part, $value);
		}

		return join(',', @values);
	};

	my $getAuthorNamePart = sub {

		my $node = shift;

		my $NameParts = {'First' => 'first-name', 'Last' => 'last-name', 'Middle' => 'middle-name'};

		return $getParts->($node, $NameParts);
	};

	if ( my $WrittenNode = $xpc->findnodes('/fbd:fb3-description/fbd:written')->[0] ) {

		my $WrittenParts = {'Date' => 'date', 'DatePublic' => 'date-public', 'Lang' => 'lang'};
		my $Written =  $getParts->($WrittenNode, $WrittenParts);
		$description .= ',Written:{' . $Written . '}' if scalar $Written;
	}

	my @Authors;
	foreach (@AuthorsPriority) {
		for my $Author ($xpc->findnodes('/fbd:fb3-description/fbd:fb3-relations/fbd:subject[@link="'.$_.'"]')) {
			push @Authors, '{Role:"' . $_ . '",' . $getAuthorNamePart->($Author) . '}';
		}
	}
	$description .= ',Authors:[' . (join ",", @Authors) . ']' if scalar @Authors;

	my @Translators;
	for my $Translator ($xpc->findnodes('/fbd:fb3-description/fbd:fb3-relations/fbd:subject[@link="translator"]')) {
		push @Translators, '{Role:"translator",' . $getAuthorNamePart->($Translator) . '}';
	}
	$description .= ',Translators:[' . (join ",", @Translators) . ']' if scalar @Translators;

	my @Relations;
	for my $ObjectNode ($xpc->findnodes('/fbd:fb3-description/fbd:fb3-relations/fbd:object')) {

		my $ObjectId    = EscString( $ObjectNode->getAttribute('id') );
		my $ObjectType  = EscString( $ObjectNode->getAttribute('link') );
		my $ObjectTitle = EscString($xpc->findnodes('./fbd:title/fbd:main', $ObjectNode)->[0]->string_value);

		push @Relations, sprintf('{id:"%s",type:"%s",title:"%s"}', $ObjectId, $ObjectType, $ObjectTitle);
	}
	$description .= ',Relations:[' . (join ",", @Relations) . ']' if scalar @Relations;

	$description .= ',ArtID:"' . EscString($ArtID) . '"' if $ArtID;

	my $FragmentStr = '';
	if ( my $FragmentNode = $xpc->findnodes('/fbd:fb3-description/fbd:fb3-fragment')->[0] ) {
		$IsTrial = 1;
		$FragmentStr = ",\n".'"fb3-fragment":{"full_length":'.$FragmentNode->getAttribute('full_length').',"fragment_length":'.$FragmentNode->getAttribute('fragment_length').'}';
	}
	
	return 'Meta:{' . $description . ',UUID:"' . $UUID . '",version:"' . $Version . '"}' . $FragmentStr . ",\n";
}

sub DecodeUtf8 {
	my $Out = shift;
	unless (Encode::is_utf8($Out)) {
		$Out = Encode::decode_utf8($Out);
	}
	return $Out;
}

sub EscString{
	my $Esc=shift;
	return unless defined $Esc;
	$Esc = DecodeUtf8($Esc." ");
	$Esc =~ s/(["\\])/\\$1/g;
	$Esc =~ s/(?:\r?\n\r?)|(?:\t)/ /g;
	$Esc =~ s/ $//;
	return $Esc;
}

my %HyphCache;
sub ProceedTextNode{
	my $Str=shift;
	my $NeedHyph = shift;
	return unless defined $Str;
	$Str = EscString($Str);
	return if $Str =~ /^\s+$/;
	my $SRC = $Str;
	if ($NeedHyph){
		$Str = $HyphCache{$SRC} || HyphString($Str);
	}
	$Str =~ s/[ \t]+/ ","/g;
	$Str =~ s/($LineBreakChars)(?![ "])/$1","/g;
	$Str =~ s/"",|,""|","$//g;
	if ($NeedHyph){
		$HyphCache{$SRC} = $Str;
		$Str =~ s/\x{AD}/","\x{AD}/g;	# Full version
	}
	$Str = '"'.$Str.'"';
	return $Str;
}

sub AnalyseNode {
	my $Node = shift || return;
	my $NodeName = shift;
	my $ParentName = shift;

	my $IsBlock = 0;
	my $IsRootBlock = 0;
	my $Printable = 1;

	if ($NodeName eq 'section' || $NodeName eq 'fb3-body' || $NodeName eq 'notes' || $NodeName eq 'notebody') {
		$IsBlock = 1;
		$IsRootBlock = 1;
		$Printable = 0;
	} elsif (($NodeName eq 'p' && $ParentName =~ /$BlockPParents/) || $NodeName eq 'title' || $NodeName eq 'subtitle' || $NodeName eq 'epigraph' ||
					$NodeName eq 'annotation' || $NodeName eq 'div' || $NodeName eq 'blockquote' || $NodeName eq 'subscription') {
		$IsBlock = 1;
	}

	return ($IsBlock, $IsRootBlock, $Printable);
}

sub HypheNOBR {
	my ($Word, $NOBRCharSeq) = @_;

#	$Word = EscString($Word);
	my $Esc = $HyphCache{$Word} || HyphString($Word);

	unless ($Esc =~ s/\xAD?([^\xAD]+)$/<nobr>$1/s) {
		$Esc = '<nobr>'.$Esc;
	}
	$Esc =~ s/\xAD//gis;

	return $Esc . $NOBRCharSeq . '</nobr>';
}

sub GetImgSize {
	my $File = shift;

	open(my $TempStdErr, ">&STDERR"); # Image::Info много и не по делу говорит, воткнём кляп.
	close STDERR;
	my $ImgInfo = Image::Info::image_info($File);
	open(STDERR, ">&", $TempStdErr); # А вот остальных послушаем.

	$ImgInfo->{height} =~ s/\D//g;
	my $Height = $ImgInfo->{height};
	$ImgInfo->{width} =~ s/\D//g;
	my $Width = $ImgInfo->{width};

	return ($Height, $Width);
}

sub trim {
  my $str = shift;
  $str =~ s/^\s+//s;
  $str =~ s/\s+$//s;
  return $str;
}

# ------------------------ Hyphenation functions ------------------------------

sub HyphString {
	use utf8;
	my $word = shift;

	my @wordArrayWithUnknownSymbols = split $RgxNonChar , $word; #собрали все слова и неизвестные символы. Для слова "пример!№?;слова" будет содержать "пример", "!№?;", "слова".

	for my $word (@wordArrayWithUnknownSymbols) {
		next if $word =~ $RgxNonChar;
		$word = HyphParticularWord($word);
	}
	return join "", @wordArrayWithUnknownSymbols;
}

sub HyphParticularWord {
	use utf8;
	my $word = shift;
	my $softHyphMinPart = 2;

	return $word if ( length($word) < 2 * $softHyphMinPart + 1 || $word eq uc($word));
	my $wordCopy = $word; #чтобы сохранить оригинальное слово. А $word заменим структурным эквивалентном
	$word =~ s/$RgxSoglasnie/S/g;
	$word =~ s/$RgxGlasnie/G/g;
	$word =~ s/$RgxZnaki/Q/g;
	while ($word =~ s/$hyphenRegexPattern/Hyphenate($1,$2,$3,\$wordCopy,$softHyphMinPart)/ge) {}
	return $wordCopy;
}

sub Hyphenate {
	use utf8;
	my ($leftFromPattern,$pattern,$rightFromPattern,$wordCopyRef,$softHyphMinPart) = @_;
	my $leftOffsetOfCurrentHyphen = length($leftFromPattern) + index($hyphenPatterns->{$pattern},&HYPHEN);
	my $rightOffsetOfCurrentHyphen = length(${$wordCopyRef}) - $leftOffsetOfCurrentHyphen; #слева дефисы не добавляются. Они добавляются справа

	substr(${$wordCopyRef}, 0, $leftOffsetOfCurrentHyphen) .= &HYPHEN
		if ($leftOffsetOfCurrentHyphen >= $softHyphMinPart && $rightOffsetOfCurrentHyphen >= $softHyphMinPart);
	#переносы ставим только если остается у нас в конце и в начале по softHyphMinPart символов

	return $leftFromPattern . $hyphenPatterns->{$pattern} . $rightFromPattern; #новую структуру кидаем в структурный эквивалент
}

1;

__DATA__

Usage:

    fb3_2_json.pl --fb3 /path/to/fb3/dir --json /path/to/json/dir [ --version <file version> ] [ --lang <file language> ] [ --art-id <id> ]

e.g.

    fb3_2_json.pl --fb3 /tmp/fb3 --json /tmp/json

    fb3_2_json.pl --fb3 /tmp/fb3 --json /tmp/json --lang ru --art-id 1234567

    fb3_2_json.pl --fb3 /tmp/fb3 --json /tmp/json --version 2.1 --lang es --art-id 1234567


