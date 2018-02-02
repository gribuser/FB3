#!/usr/local/bin/perl

use 5.006;
use strict;
use warnings;
use FB3::Convert;
use XML::Diff;
use File::Basename;
use Data::Dumper;
use utf8;
use Encode;
use XML::LibXML;
use Test::More;

plan tests => 1;


diag( "Testing result of body.xml, Perl $], $^X" );

my $Diff = XML::Diff->new();

my $DIR = dirname(__FILE__).'/examples';

opendir(my $DH, $DIR) || die "Can't opendir $DIR: $!";
my @Epubs = grep { $_ =~ /\d+\.epub$/ && -f $DIR."/".$_ } readdir($DH);
closedir $DH;

foreach my $EpubFile (@Epubs) {

  $EpubFile =~ m/^(\d+)\.epub$/;
  my $FNum = $1;

  diag("Testing ".$DIR.'/'.$EpubFile);
  
  my $Obj = new FB3::Convert(
    'source' => $DIR.'/'.$EpubFile,
    'destination_dir' => '/tmp/ddd',
    'verbose' => 0,
  );

  $Obj->Reap();
  my $FB3Path =  $Obj->FB3Create();
  my $ValidErr = $Obj->Validate();
  if ($ValidErr) {
    diag($ValidErr);
    $Obj->Cleanup();
    _Clean($Obj);
    exit;
  }

  my $OldXml = $DIR.'/body'.$FNum.'.xml';
  die("file $OldXml not found") unless -f $OldXml;
  my $NewXml = $FB3Path.'/fb3/body.xml';

  _Diff($Obj,$OldXml,$NewXml);

  $Obj->Cleanup();
  _Clean($Obj);

  ok(1,'Test ok');
  exit;
}

sub _Diff {
  my $X = shift;
  my $OldFile = shift;
  my $NewFile = shift;

  open my $fho, '<', $OldFile or die $!;
  my $OldXml;
  map {$OldXml .= $_} <$fho>;
  close $fho;
  $OldXml = Encode::decode_utf8(Encode::encode_utf8($OldXml));
  $OldXml =~ s#xmlns="http://www.fictionbook.org/FictionBook3/body"##g;
#  print $OldXml;

  open my $fhn, '<', $NewFile or die $!;
  my $NewXml;
  map {$NewXml .= $_} <$fhn>;
  $NewXml = Encode::decode_utf8(Encode::encode_utf8($NewXml));
  close $fhn;
  $NewXml =~ s#xmlns="http://www.fictionbook.org/FictionBook3/body"##g;
#  print $NewXml;

  my $Diffgram = $Diff->compare(-old => $OldXml, -new => $NewXml);

#print $Diffgram;

  my $XMLDoc = XML::LibXML->new();
  my $NodeDoc = $XMLDoc->parse_string($Diffgram) || die "Can't parse! ".$!;
  my $Root = $NodeDoc->getDocumentElement;

 # print $Root->nodeName();
  my $Err;
  foreach my $Event ( $Root->getChildnodes ) {
    my $EventName = $Event->nodeName();
    my $EventNodeName = $Event->getAttribute('first-child-of') || $Event->getAttribute('follows');

    my $DiffError;
    foreach my $NodeDiff ($Event->getChildnodes) {
      my $DiffName = $NodeDiff->nodeName();

      if ( $DiffName =~ /^xvcs:.+$/ ) {

        if ($DiffName eq 'xvcs:attr-update') {

          if ($NodeDiff->getAttribute('name') =~ /^(id|xlink:href)$/i) { #it's OK event
            next;
          }

          $DiffError .= $DiffName."\n";
          $DiffError .= "  name: ".$NodeDiff->getAttribute('name')."\n";
          $DiffError .= "  old: ".$NodeDiff->getAttribute('old-value')."\n";
          $DiffError .= "  new: ".$NodeDiff->getAttribute('new-value');
          next;

        }

        if ($DiffName eq 'xvcs:attr-delete' || $DiffName eq 'xvcs:attr-insert') {
          $DiffError .= $DiffName."\n";
          $DiffError .= "  name: ".$NodeDiff->getAttribute('name')."\n";
          $DiffError .= "  value: ".$NodeDiff->getAttribute('value');
          next;
        }

        $DiffError .= $DiffName; #all other errors

      } else {
        $DiffError .= $X->InNode($Event);
      }

    }

    if ($DiffError) {
      $Err .= "Critical diff!\n";
      $Err .= " event: ".xtrim($EventName)."\n";
      $Err .= " node: ".$EventNodeName."\n";
      $Err .= " content: ".$DiffError."\n\n";
    }

  }

  if ($Err) {
    diag($Err);
    $X->Cleanup();
    _Clean($X);
    exit;
  }

  return 1;
}

sub xtrim {
  my $str = shift;
  $str =~ s/.+:([a-z0-9\-_]+)$/$1/i;
  return $str;
}

sub _Clean {
  my $X = shift;
  
  diag("Clean src ".$X->{'DestinationDir'});
  $X->ForceRmDir($X->{'DestinationDir'});
  
}

