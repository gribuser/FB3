#!/usr/bin/perl
use strict;
package cleanFB2;
use strict;
use XML::Parser;
use XML::LibXSLT;
use XML::LibXML;
use utf8;

#=============================================================
if (!$ARGV[3]){print "CutPart: makes trial fragment from fb2
Usage:

CutPart.pl <inputfile.fb2> <outputfile.fb2> <chars_in_result> <art-id> <file-promotext> <promo-id>\n";
exit 0;}
#=============================================================


my ($InFIle, $OutFIle, $CutChars, $ArtID, $PromoTextFile, $PromoId) = @ARGV;

$PromoId ||= 'litres_trial_promo';
$PromoId = '#' . $PromoId unless $PromoId =~ /^#/;

my %escapes=(
  '&'	=> '&amp;',
  '<'	=> '&lt;',
  '>'	=> '&gt;',
  '"'	=> '&quot;',
  "'"	=> '&apos;'
);

sub xmlescapeLite {
	$b=shift;
  $_=$b;
  s/([&<>])/$escapes{$1}/gs;
  $_;
}


sub xmlescape {
	$b=shift;
  $_=$b;
  s/([&<>\'\"])/$escapes{$1}/gs;
  $_;
}

sub stripSpace{
	$_=shift;
	s/\A\s*(.*?)\s*\Z/$1/;
	return $_;
}

my $SectionsDeep=0;
my @XMLBody;
my $InBody;
my $InNotesBody;
my $CharsProcessed=0;
my $Finita=0;
my $FakeP=0;
my $FirstBody=1;
my $XLinkPrefix = 'l';
my %IDS;

sub GetPromoText {
  my $PromoTextF = shift;
  my $Out = '';
  open(PTF, "<:utf8", $PromoTextF) || die "Cannot open file '$PromoTextF'\n$!\n";
  $Out = join('', <PTF>);
  close PTF;
  return $Out;
  # For example:
  #<section id="litres_trial_promo">
  #<title><p>Конец ознакомительного фрагмента.</p></title>
  #<p>Текст предоставлен ООО «ЛитРес».</p>
  #<p>Прочитайте эту книгу целиком, <a $XLinkPrefix:href="$ArtURL">купив полную легальную версию</a> на ЛитРес.</p>
  #<p>Стоимость полной версии книги 59,50р. (на 17.01.2012).</p>
  #<p>Безопасно оплатить книгу можно банковской картой Visa, MasterCard, Maestro, со счета мобильного телефона, с платежного терминала, в салоне МТС или Связной, через PayPal, WebMoney, Яндекс.Деньги, QIWI Кошелек, бонусными картойами или другим удобным Вам способом.</p>
  #</section>
}

my $PromoText;
$PromoText = GetPromoText($PromoTextFile) if $PromoTextFile;

my $CUttingParser = XML::Parser->new(Handlers => {
	Start => sub {
		my ($expat, $elem, %Params) = @_;

		if ($elem eq "section"){
			$SectionsDeep++;
		}

		if ($elem eq 'body' && ($Params{'name'} eq 'notes') && !$FirstBody){
			$InNotesBody=1;
			$InBody=0;
		} elsif ($elem eq "body"){
			$InNotesBody=0;
			$InBody=1;
			$FirstBody=0;
		} elsif ($elem eq "FictionBook"){
			for (keys %Params){
				if ($Params{$_} eq 'http://www.w3.org/1999/xlink'){
					s/xmlns://;
					$XLinkPrefix = $_;
				}
			}
		}
		if ($elem =~ /^(title|cite|epigraph)$/){
			$FakeP=1;
		}

		return if $Finita && $InBody  && !$InNotesBody;

    if ( exists $Params{'id'} ) {
      $IDS{$Params{'id'}} = 1;
    }

		my $Tag="<$elem";
		for (keys(%Params)){
			$Tag.=" $_=\"".stripSpace(xmlescape($Params{$_}))."\"";
		}
		push(@XMLBody,"$Tag>");
	},
	Char  => sub {
		return if $Finita && $InBody  && !$InNotesBody;
		my $XText=$_[1];
		$CharsProcessed+= length($XText) if $InBody;
		push(@XMLBody,xmlescapeLite($XText));
	},
	End => sub {
		my $elem=$_[1];
		if ($elem eq "section"){
			$SectionsDeep--;
		}
		$InBody = 0 if $elem eq 'body';
		if (!$Finita && !$FakeP && $elem =~ /^(p|v|section)$/ and $CharsProcessed >= $CutChars){
			$Finita=1;
      if ($PromoText){
        # бум генерить новый промотекст, закроем все секции, они нам не нужны
        if ($elem eq 'p'){
          push @XMLBody,q{</p>};
        } elsif ($elem eq 'v') {
          push @XMLBody,q{</v></stanza></poem>};
        } elsif ($elem eq 'section'){
          push @XMLBody,q{</section>};
        }
      } else {
        # старый промо текст
        if ($elem eq 'p'){
          push @XMLBody,qq{</p><p>Конец ознакомительного фрагмента. <a $XLinkPrefix:href="http://www.litres.ru/pages/biblio_book/?art=$ArtID">Полный текст доступен на www.litres.ru</a></p>};
        } elsif ($elem eq 'v') {
          push @XMLBody,qq{</v><v>Конец ознакомительного фрагмента. <a $XLinkPrefix:href="http://www.litres.ru/pages/biblio_book/?art=$ArtID">Полный текст доступен на www.litres.ru</a></v></stanza></poem>};
        } elsif ($elem eq 'section'){
          push @XMLBody,qq{<p>Конец ознакомительного фрагмента. <a $XLinkPrefix:href="http://www.litres.ru/pages/biblio_book/?art=$ArtID">Полный текст доступен на www.litres.ru</a></p></section>};
        }
      }
			for (1..$SectionsDeep){
				push @XMLBody,'</section>';
			}

      # новый промо текст с ЧПУ вставляем самой последней секцией
      push @XMLBody, $PromoText if ($PromoText);

			push @XMLBody, '</body>';
		}
		return if $Finita && ($InBody || $elem eq 'body' && !$InNotesBody);

		if ($elem =~ /^(title|cite|epigraph)$/){
			$FakeP=0;
		}

		unless ($XMLBody[$#XMLBody] =~ s/^(<$elem[^>]+[^\/])>$/$1\/>/){
			push(@XMLBody,"</$elem>");
		}
	}
});

$CUttingParser->parsefile($InFIle);

my $FixParser = XML::Parser->new(Handlers => {
  Start => sub {
    my ($expat, $elem, %Params) = @_;

    if ( $elem eq 'a' ) {
      if ( exists $Params{"$XLinkPrefix:href"} && $Params{"$XLinkPrefix:href"} =~ /^#(.+)$/ ) {
        my $link = $1;
        $Params{"$XLinkPrefix:href"} = $PromoId unless $IDS{$link};
      }
    }

    my $Tag="<$elem";

    for ( keys %Params ) {
      $Tag .= " $_=\"" . stripSpace(xmlescape($Params{$_})) . '"';
    }

    push(@XMLBody, "$Tag>");
  },
  Char  => sub {
    push(@XMLBody, xmlescapeLite($_[1]));
  },
  End => sub {
    my $elem = $_[1];

    unless ($XMLBody[$#XMLBody] =~ s/^(<$elem[^>]+[^\/])>$/$1\/>/) {
      push(@XMLBody, "</$elem>");
    }
  },
});

my $ToFix = '<?xml version="1.0" encoding="utf-8"?>' . join( '', @XMLBody );
@XMLBody = ();

$FixParser->parse($ToFix);

my $parser = XML::LibXML->new();
my $xslt = XML::LibXSLT->new();
my $source;

eval {
	$source = $parser->parse_string(join '',@XMLBody);
};

if ($@){
	die join(', ',@ARGV).$@;
}

open OUTFILE, ">$OutFIle";
binmode OUTFILE;
{
	no warnings;
	print OUTFILE join '',@XMLBody;
}
close OUTFILE;
