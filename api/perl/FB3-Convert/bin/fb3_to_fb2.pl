#!/usr/local/bin/perl

use strict;
use File::ShareDir qw/dist_file/;
use Getopt::Long;
use OPC;
use XML::LibXML;
use XML::LibXSLT;
use MIME::Base64;
use Image::LibRSVG;
use File::Temp qw/tempfile/;
use Encode;
use Text::Unidecode;
use URI::Escape;
use JSON::XS;
use utf8;
use open OUT => ':utf8';

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
  XSL_FB3_TO_FB2_DESC => dist_file("FB3-Convert", "fb3_2_fb2_descr.xsl"),
  XSL_FB3_TO_FB2_BODY => dist_file("FB3-Convert", "fb3_2_fb2_body.xsl"),
};

use constant {
  NS_FB3_DESCRIPTION => 'http://www.fictionbook.org/FictionBook3/description',
  NS_FB3_BODY => 'http://www.fictionbook.org/FictionBook3/body'
};

my %OPT;
GetOptions(
  'verbose' => \$OPT{'verbose'},           
  'help' => \$OPT{'help'},
  'force' => \$OPT{'force'},
  'fb3=s' => \$OPT{'fb3'},
  'fb2=s' => \$OPT{'fb2'},
	'fb2xsd=s' => \$OPT{'fb2xsd'},
	'genremap=s' => \$OPT{'genremap'},
) || help();

#если вызван ключик --help или нет ни единого ключа
help() if $OPT{'help'} || !grep {defined $OPT{$_}} keys %OPT;

die ("param -fb3 not defined") unless defined $OPT{'fb3'};
die ("param -fb3: file '".$OPT{'fb3'}."' not exists") unless -e $OPT{'fb3'};
die ("param -fb2 not defined") unless defined $OPT{'fb2'};
die ("param -fb2xsd not defined") unless $OPT{'fb2xsd'};
die ("param -fb2xsd: there is no such file '".$OPT{'fb2xsd'}."'") unless -f $OPT{'fb2xsd'};
$OPT{'genremap'} //= dist_file("FB3-Convert", "fb3_to_fb2_genre.json");

#CHECK --fb2,--fb3 
my $FileName = $OPT{'fb3'};
$FileName =~ s/.*?([^\/]+)$/$1/;
$FileName =~ s/\.fb3$//;
#если директория, кладем в нее под именем fb3
$OPT{'fb2'} =~ s/\/$//;
$OPT{'fb2'} = $OPT{'fb2'}.'/'.$FileName if -d $OPT{'fb2'};
#еще проверка, не сунули нам неправильную директорию?
my $Fb2Dir = $OPT{'fb2'};
$Fb2Dir =~ s/([^\/]+)$//;
die ("param fb2: dir '$Fb2Dir' not exists") unless -d $Fb2Dir;
$OPT{'fb2'} .= '.fb2' unless $OPT{'fb2'} =~ m/\.fb2$/;

#все ок, поехали
print "Start convert FB3 (".$OPT{'fb3'}.") to FB2 (".$OPT{'fb2'}.")\n" if $OPT{'verbose'};

my $Parser = new XML::LibXML;
my $Doc = new XML::LibXML::Document;

my (@FB2XML, @FB2ImgXML, $NS, %NS);
my $FB3Package = OPC->new( $OPT{'fb3'} );

#Находим Description?
my %DescrRelation = $FB3Package->RelationByType( '/_rels/.rels', RELATION_TYPE_FB3_BOOK );
my $DescrRelsPartName = $DescrRelation{'TargetFullName'};

#Находим body
my $BodyRelsPartName = $DescrRelsPartName;
$BodyRelsPartName =~ s/^(.*)\/([^\/]*)$/$1\/\_rels\/$2\.rels/;
my %BodyRelation = $FB3Package->RelationByType( $BodyRelsPartName, RELATION_TYPE_FB3_BODY );

#Картинки соберем первыми, до всяких преобразований xslt

#а где у нас  описание body?
my $BodyRelsPartName = $BodyRelation{'TargetFullName'};
$BodyRelsPartName =~ s/^(.*)\/([^\/]*)$/$1\/\_rels\/$2\.rels/;

#где у нас обложка?
my @Img;
my ($CoverRelation) = $FB3Package->RelationsByType( '/_rels/.rels', RELATION_TYPE_OPC_THUMBNAIL );
if ($CoverRelation->{'TargetFullName'}) {
  $CoverRelation->{IsCover} = 1;
  push @Img, $CoverRelation;
}

#читаем картинки
push @Img, $FB3Package->RelationsByType( $BodyRelsPartName, RELATION_TYPE_FB3_IMAGES );

my (%ImgRels, %ImgReverse);
my (%LinkRels);
foreach my $Img (@Img) {
  print "Processing img ".$Img->{'Id'}."\n" if $OPT{'verbose'};
  
  my $ImgType;
  my $ImgContent = $FB3Package->PartContents($Img->{'TargetFullName'});
  my $ImgType = $FB3Package->PartContentType($Img->{'TargetFullName'});
  
  #SVG конвертим в PNG
  if ( $ImgType eq 'image/svg' || $ImgType eq 'image/svg+xml' || $Img->{'TargetFullName'} =~ /\.svg$/ ) {
    $ImgContent = Svg2Png($ImgContent);
    $ImgType = 'image/png';
    $Img->{'TargetFullName'} = SvgUnique($Img->{'TargetFullName'}, \@Img);
  } else {
    $ImgType = 'image/png' if $Img->{'TargetFullName'} =~ /\.png$/;
    $ImgType = 'image/jpeg' if $Img->{'TargetFullName'} =~ /\.(jpg|jpeg)$/;
    $ImgType = 'image/gif' if $Img->{'TargetFullName'} =~ /\.gif$/;
  }
  
  my $NewImgId = $Img->{'TargetFullName'};
	$NewImgId = URI::Escape::uri_unescape($NewImgId);
	$NewImgId = DecodeUtf8($NewImgId);
	$NewImgId = TransLitGeneral($NewImgId) if $NewImgId =~ /[А-Яа-я]/;
  $NewImgId =~ s#/#_#g;
  $NewImgId =~ s/^_//;
  if ($ImgType =~ /\/(.+)$/) {
    $NewImgId .= '.'.$1 unless $NewImgId =~ /\.(png|gif|jpg|jpeg)$/;
  }
  
  next if exists $ImgReverse{$NewImgId}; #иногда описания картинок совпадают. например обложка залетает дважды из описаний
  
  $Img->{NewId} = $ImgRels{$Img->{'Id'}} = $NewImgId;
  $ImgReverse{$NewImgId} = 1;
   
  push @FB2ImgXML, '<binary content-type="'.$ImgType.'" id="'.$NewImgId.'">'.MIME::Base64::encode($ImgContent).'</binary>';
}

#работаем с DESCRIPTION
my $DescrXML = $FB3Package->PartContents($DescrRelsPartName);
my $xc = XML::LibXML::XPathContext->new($Parser->parse_string($DescrXML)); 
$xc->registerNs('fb3', &NS_FB3_DESCRIPTION); 


#запихаем в xml данные обложки
if ($Img[0]->{'IsCover'} &&  (my $RootDescr = $xc->findnodes("/fb3:fb3-description")->[0]) ){
  my $CoverElement = $Doc->createElement('coverpage');
  $CoverElement->setAttribute('href'=> $Img[0]->{'NewId'});
  $RootDescr->appendChild($CoverElement);
  $DescrXML = $RootDescr->toString();
}

#тянем preamble из description
my @Preamble;
if (my $Pr = $xc->findnodes("/fb3:fb3-description/fb3:preamble")->[0]) {
   map { push @Preamble,  CopyNode($_);} $Pr->childNodes();
}

my $FB2Descr = TransformXML($DescrXML, XSL_FB3_TO_FB2_DESC);
print "Transform Description ok\n" if $OPT{'verbose'};

my @NewGenreNodes = $xc->findnodes("/fb3:fb3-description/fb3:fb3-classification/fb3:subject/text()");
my @NewGenres = map $_->data, @NewGenreNodes;
my %Genre2GenreAlias = NewGenreToOldMap(@NewGenres);

my $Node = RootNode($FB2Descr, ['/fb:description/fb:title-info/fb:genre', \%Genre2GenreAlias, 1]);
push @FB2XML, '<description>'.$Node->{'Content'}.'</description>'; #собираем контент
map {$NS{$_} = $Node->{NS}->{$_}} keys %{$Node->{NS}}; #собираем NS

#работаем с BODY
my $BodyXML = $FB3Package->PartContents( $BodyRelation{'TargetFullName'} );
my $xc = XML::LibXML::XPathContext->new($Parser->parse_string($BodyXML)); 
$xc->registerNs('fb3', &NS_FB3_BODY); 

#запихаем в xml preamble
if (@Preamble &&  (my $RootBody = $xc->findnodes("/fb3:fb3-body")->[0]) ){
  my $PreambleElement = $Doc->createElement('preamble');
  map { $PreambleElement->appendChild($_) } @Preamble;
  $RootBody->appendChild($PreambleElement);
  $BodyXML = $RootBody->toString();
}

## change span id
#span нужно вынести в ближайший родительский block-level
#span затем будет выкушен в xsl
my $ChangedBySpan=0;
foreach my $Span ($xc->findnodes("/fb3:fb3-body/fb3:section//fb3:p//fb3:span")) {
  my $SpanID = $Span->getAttribute('id') || next;
  my $Parent = $Span;
  while ($Parent = $Parent->parentNode()) {
    if (lc($Parent->nodeName()) eq 'p') { #вроде как кроме <p> нам некуда переехать?
      my $ParentID = $Parent->getAttribute('id');
      if ($ParentID) {
        #уже есть id, придется менять линки в документе на него
        $LinkRels{$SpanID} = $ParentID; 
      } else {
        $Parent->setAttribute('id' => $SpanID);
        $ChangedBySpan = 1;
      }
      last;
    }
  }
}

if ($ChangedBySpan) {
  my $RootForSpan = $xc->findnodes("/fb3:fb3-body")->[0];
  $BodyXML = $RootForSpan->toString();
}
## /change span id

my $FB2Body = TransformXML($BodyXML, XSL_FB3_TO_FB2_BODY);
print "Transform Body ok\n" if $OPT{'verbose'};
my $Node = RootNode($FB2Body);

push @FB2XML, $Node->{'Content'}; #собираем контент
map {$NS{$_} = $Node->{NS}->{$_}} keys %{$Node->{NS}}; #собираем NS

#собираем NS
$NS .= join (" ", map{$_.'="'.$NS{$_}.'"'} keys %NS); 
$NS = " ".$NS if $NS; 

my $OUT = '<?xml version="1.0" encoding="UTF-8"?>
<FictionBook'.$NS.'>'.join('',@FB2XML).join('',@FB2ImgXML).'</FictionBook>';

#проверка валидности полученного FB2
my $Schema = XML::LibXML::Schema->new(location => $OPT{'fb2xsd'});
my $FB2 = $Parser->parse_string($OUT);
eval { $Schema->validate($FB2) };
die "Schema validation error for file $OPT{'fb3'}: $@" if $@ && !$OPT{'force'};

#Все прошло ок, сохраняем файл
print "Save file to ".$OPT{'fb2'}."\n" if $OPT{'verbose'};
open F,">".$OPT{'fb2'} || die "can't open file $OPT{'fb2'}: $!";
binmode(F,':utf8');
print F $OUT;
close F;

sub CopyNode {
  my $Node = shift;
  
  #текстовую  не трогаем
  return $Node if $Node->nodeName eq '#text';

  #копируем атрибуты
  my $El= $Doc->createElement($Node->nodeName);
  foreach my $Att ($Node->attributes){
    next if $Att->nodeName =~ /xmlns(?::|$)/;
    $El->setAttribute($Att->localname, $Att->value);
  }
  
  #копируем чайлд-ноды
  foreach my $Child ($Node->childNodes){
    $El->appendChild( CopyNode($Child) );
  }
 
  return $El;
}

sub Svg2Png {
  my $Img = shift;
   
  my $Rsvg = new Image::LibRSVG();
  my $Formats  = $Rsvg->getSupportedFormats();    
    
  die "can't convert svg to png or jpeg. librsvg not supported PNG" unless $Rsvg->isFormatSupported("png");
 
  $Rsvg->loadImageFromString($Img);
  
  my ($TmpFH, $TmpFile) = File::Temp::tempfile(UNLINK => 1);
  $Rsvg->saveAs( $TmpFile,  'png') || die "can't convert svg: $!";
  
  my $Content;
  while (my $row = <$TmpFH>) {
    $Content .= $row;  
  }
  close $TmpFH;
 
  return $Content,
}

sub TransformXML{
	my $XML=shift;
	my $XSL=shift;

	my $Xslt = XML::LibXSLT->new();
  
  #все .svg у нас теперь .png ВЕЗДЕ
  $Xslt->register_function('LTR', 'RplId', sub {
      my $Str  = shift;
      if ($Str =~ /^(#)?(.+)/) { # может попасться якорь "#", учитываем
        $Str = $1.$ImgRels{$2} if exists $ImgRels{$2};
        $Str = $1.$LinkRels{$2} if exists $LinkRels{$2};
      }
      return $Str;
    }
  );

  $Xslt->register_function('LTR', 'RplLocalHref', sub {
      my $Str    = shift;
      my $Prefix = shift;
      if ($Str =~ /^#(.+)/) {
        $Str = '#'.$Prefix.$1;
      }
      return $Str;
    }
  );

  my $Source = $Parser->parse_string($XML);
	my $StyleDoc = $Parser->parse_file($XSL);
	my $Stylesheet = $Xslt->parse_stylesheet($StyleDoc);

	return $Stylesheet->output_string($Stylesheet->transform($Source));
}

#вытащим весь корень из части xml,
#собираем NS из частей, потом запихнем их в общий корень
sub RootNode {
  my $XML=shift;
  my $Replace=shift; # ['xpath', {'содержимое' => 'замена1', 'содержимое2' => 'замена2',...}, delete bool]

  my $xc = XML::LibXML::XPathContext->new($Parser->parse_string($XML)); 
  $xc->registerNs('fb', 'http://www.gribuser.ru/xml/fictionbook/2.0'); 
  
  if ($Replace) {

		my @NodesForUnbind;
		my $GenresCount = 0;
    #ищем ноду на замену
    foreach my $Genre ($xc->findnodes($Replace->[0])) {
      my $GenreName = $Genre->firstChild->toString();
      
      if ($Replace->[1]->{$GenreName}) {
        #меняем содержимое
        $Genre->firstChild->setData($Replace->[1]->{$GenreName});
				$GenresCount++;
      } elsif ($Replace->[2]) {
        #не нашли замену, ноду отложим для удаления
        push @NodesForUnbind, $Genre;
      }
    }

		unless ($GenresCount) { # Ни одного нормального жанра.
			my $Genre = shift @NodesForUnbind; # Первый оставим
			$Genre->firstChild->setData('unrecognised'); # как "неопределённый"
		}
		map {$_->unbindNode()} @NodesForUnbind; # Удалим неподходящие жанры.

  }

  my $Node = $xc->findnodes("/")->[0]->firstChild;

  my %Attrs;
  foreach ( $Node->getAttributes() ) {
    $Attrs{$_->name} = $_->value;
  }
  
  return {
    NS => \%Attrs, 
    Content => join ("",map {$_->toString()} $Node->childNodes())
  }
 
}



#следим чтобы имя не повторилось
sub SvgUnique {
  my $Name = shift;
  my $Imgs = shift;
  return $Name unless $Name =~ /.svg$/;
  
  my $OldName = $Name;
  $Name =~ s/\.svg$/.png/;

  my $c=0;
  while (grep {$_->{'TargetFullName'} eq $Name} @$Imgs) {
    $Name = 'U'.sprintf('%04d',rand(9999)).'_'.$Name;
    $c++;
    die "to big loop! make something" if $c>=1000; 
  }

  return $Name;  
}

sub NewGenreToOldMap {
  my $GenreMapPath = $OPT{'genremap'};
  die "genres map file '$GenreMapPath' doesn't exist" unless -e $GenreMapPath;
  
  my $GenreMapString = do {
    open my $fh, '<', $GenreMapPath;
    local $/;
    <$fh>;
  };
  my $GenreMap = eval {JSON::XS->new->utf8->decode($GenreMapString)};
  if ($@) {
    die "Seems like genres map file '$GenreMapPath' contains invalid JSON. Error occured '$@'";
  }
  die "genres map file '$GenreMapPath' doesn't contain JSON object" unless ref $GenreMapPath ne 'HASH';
  return %$GenreMap;
}

sub DecodeUtf8 {
  my $Out = shift;
  if ($Out && !Encode::is_utf8($Out)) {
    $Out = Encode::decode_utf8($Out);
  }
  return $Out;
}

sub TransLitGeneral {
  $_ = shift;

  s/ё/yo/g;
  s/й/yi/g;
  s/ю/yu/g;
  s/ь//g;
  s/ч/ch/g;
  s/[щш]/sh/g;
  s/ы/yi/g;
  s/э/yе/g;
  s/я/ya/g;
  s/Ё/Yo/g;
  s/Й/Yi/g;
  s/Ю/Yu/g;
  s/Ь//g;
  s/Ч/Ch/g;
  s/[ЩШ]/Sh/g;
  s/Ы/Yi/g;
  s/Э/Ye/g;
  s/Я/Ya/g;
  tr/ÉÓÁéóáĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĲĳĴĵĶķĸĹĺĻļĽľĿŀŁłŃńŅņŇňŉŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚŜśŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſƒƠơƯưǍǎǏǐǑǒǓǔǕǖǗǘǙǚǛǜǺǻǼǽǾǿђѓєѕіїјљњћќўџҐґẀẁẂẃẄẅẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳẴẵẶặẸẹẺẻẼẽẾếỀềỂỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữỰựỲỳỴỵỶỷỸỹ№/EOAeoaAaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiJjJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoCoRrRrRrSSssSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzffOoUuAaIiOoUuUuUuUuUuAaAaOohgesiijjhhkyjGgWwWwWwAaAaAaAaAaAaAaAaAaAaAaAaEeEeEeEeEeEEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUuUuYyYyYyYyN/;
  tr/цукенгзхфвапролджсмитбъЦУКЕНГЗХФВАПРОЛДЖСМИТБЪ/cukengzhfvaproldjsmitb'CUKENGZHFVAPROLDJSMITB'/;

  Text::Unidecode::unidecode($_);
}

sub help {
  print <<_END
  
  USAGE: fb3_to_fb2.pl --fb3= --fb2= --fb2xsd= [--genremap=] [--verbose] [--help]
  
  --help : print this text
  --verbose : print processing status
  --fb3 : path to FB3 file
  --fb2 : path to dir or filename for saving completed FB2 file
  --fb2xsd : path to FB2 XSD schema (see https://github.com/gribuser/fb2/blob/master/FictionBook.xsd)
  --genremap : path to json file containing mapping from FB3 to FB2 genre names.
               If omitted static file fb3_to_fb2_genre.json file lying near the
               script is used
  --force : ignore validation error
  
_END
;
exit;
}
