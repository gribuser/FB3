#!/usr/local/bin/perl

use 5.006;
use strict;
use warnings;
use XML::Diff;
use File::Basename;
use Data::Dumper;
use utf8;
use Encode;
use XML::LibXML;
use Test::More;
use File::Temp qw/tempfile/;
use File::ShareDir qw/dist_dir/;

diag( "Testing result of fb3->fb, Perl $], $^X" );

my $FB3M;
eval {
  $FB3M = dist_dir('FB3');
}; 
if ($@) {
  diag('FB3 module not found. Please install before.');
  exit;
}

my $FB2XSD = $FB3M.'/FictionBook.xsd';
unless (-f $FB2XSD) {
  diag('FictionBook.xsd is required, but not found. Please update FB3 module.');
  exit;
}

my $Diff = XML::Diff->new();

my $DIR = dirname(__FILE__).'/examples/fb3_to_fb2';
opendir(my $DH, $DIR) || die "Can't opendir $DIR: $!";
my @FB3s = grep { $_ =~ /.+\.fb3$/ && -f $DIR."/".$_ } readdir($DH);
closedir $DH;
diag("Testing FB3->FB2 files");
foreach my $FB3File (sort{Num($a,'fb3')<=>Num($b,'fb3')} @FB3s ) {
  $FB3File =~ m/^(.+)\.fb3$/;
  my $FName = $1;

  my $OldXml = $DIR.'/'.$FName.'.xml';

  diag("Testing ".$DIR.'/'.$FB3File.' and compare with '.$OldXml);
  unless ( -f $OldXml ) {
    diag("file $OldXml not found");
    next;
  }

  my $TmpFile = File::Temp->new(UNLINK=>1, SUFFIX=>'.fb2');

  my $Cmd = 'perl '.dirname(__FILE__).'/../bin/fb3_to_fb2.pl --fb3='.$DIR.'/'.$FB3File.' --fb2='.$TmpFile.' --fb2xsd='.$FB2XSD.' 2>&1 1>/dev/null';
  `$Cmd`;

  unless (-s $TmpFile) {
    diag("Error of convert fb3->fb2");
    exit;
  } 

  ok( _Diff($OldXml, $TmpFile), $FB3File );
  unlink $TmpFile if -f $TmpFile;
}
done_testing();
exit;

sub Num {
  my $Fname=shift;
  my $fmt=shift;
  $Fname =~ /(\d+)\.$fmt/;
  $Fname=$1;
  return $Fname;
}

sub _Diff {
  my $OldFile = shift;
  my $NewFile = shift;

  open my $fho, '<', $OldFile or die $!;
  my $OldXml;
  map {$OldXml .= $_} <$fho>;
  close $fho;
  $OldXml = Encode::decode_utf8(Encode::encode_utf8($OldXml));

  open my $fhn, '<', $NewFile or die $!;
  my $NewXml;
  map {$NewXml .= $_} <$fhn>;
  $NewXml = Encode::decode_utf8(Encode::encode_utf8($NewXml));
  close $fhn;

  my $Diffgram = $Diff->compare(-old => $OldXml, -new => $NewXml);
  my $XMLDoc = XML::LibXML->load_xml(string=>$Diffgram) || die "Can't parse! ".$!;

  my $Root = $XMLDoc->getDocumentElement;

  my $Err;
  foreach my $Event ( $Root->getChildnodes ) {
    my $EventName = $Event->nodeName();

    my $EventNodeName;
    my $ContainerName;
    if ($EventNodeName = $Event->getAttribute('first-child-of')) {
      $ContainerName = 'first-child-of';
    } elsif ($EventNodeName = $Event->getAttribute('follows')){
      $ContainerName = 'follows';
    }

    my $DiffError;
    foreach my $NodeDiff ($Event->getChildnodes) {
      my $DiffName = $NodeDiff->nodeName();

      if ( $DiffName =~ /^xvcs:.+$/ ) {

        if ($DiffName eq 'xvcs:attr-update') {

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
        $DiffError .= substr($Event,0,500).'...';
      }

    }

    if ($DiffError) {
      $Err .= "Critical diff!\n";
      $Err .= " event: ".xtrim($EventName)."\n";
      $Err .= " ".$ContainerName.": ".$EventNodeName."\n";
      $Err .= " content: [".$DiffError."]\n\n";
    }

  }

  if ($Err) {
    diag($Err);
    unlink $NewFile;
    return 0;
  }

  return 1;
}

sub xtrim {
  my $str = shift;
  $str =~ s/.+:([a-z0-9\-_]+)$/$1/i;
  return $str;
}

