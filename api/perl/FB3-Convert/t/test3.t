#!/usr/local/bin/perl

use 5.006;
use strict;
use warnings;
use XML::Diff;
use File::Basename;
use Data::Dumper;
use utf8;
use Encode;
use FB3;
use XML::LibXML;
use Test::More;
use File::Temp qw/tempfile/;
use File::ShareDir qw/dist_dir/;

diag( "Testing cutfb3, Perl $], $^X" );

my $Diff = XML::Diff->new();

my $DIR = dirname(__FILE__).'/examples/cutfb3';
opendir(my $DH, $DIR) || die "Can't opendir $DIR: $!";
my @FB3s = grep { $_ =~ /.+\.fb3$/ && -f $DIR."/".$_ } readdir($DH);
closedir $DH;
foreach my $FB3File (sort{Num($a,'fb3')<=>Num($b,'fb3')} @FB3s ) {
  $FB3File =~ m/^((\d+)_(.+))\.fb3$/;
  my $CutChars = $2;
  my $FName = $1;

  my $OldXml = $DIR.'/'.$FName.'.xml';

  diag("Testing ".$DIR.'/'.$FB3File.' and compare with '.$OldXml);

  unless ( -f $OldXml ) {
    diag("file $OldXml not found");
    next;
  }

  my $TmpFb3 = File::Temp->new(UNLINK=>1, SUFFIX=>'.fb3');

  my $Cmd = 'perl '.dirname(__FILE__).'/../bin/cutfb3.pl --in='.$DIR.'/'.$FB3File.' --out='.$TmpFb3.' --chars='.$CutChars.' 2>&1 1>/dev/null';
  `$Cmd`;

  unless (-s "$TmpFb3") {
    diag("Error of cut fb3");
    exit;
  } 

  my $TmpDir = File::Temp::tempdir( CLEANUP => 1 );
  my $FB3TmpDir = $TmpDir.'/unzipped_'.File::Basename::basename($TmpFb3);
  my $UnzipMessage = `/usr/bin/unzip -o -d $FB3TmpDir $TmpFb3 2>&1`;
  die "Unzipping fb3 error: $UnzipMessage" if $?;
  my $FB3Package = FB3->new( from_dir => $FB3TmpDir );
  my $FB3Body = $FB3Package->Body;

  my $TmpXml = $FB3TmpDir.$FB3Body->{'name'};

  ok( _Diff($OldXml, $TmpXml), $FB3File );
  unlink $TmpFb3 if -f $TmpFb3;
}
done_testing();
exit;

sub Num {
  my $Fname=shift;
  my $fmt=shift;
  $Fname =~ /(\d+)_(\d+)\.$fmt/;
  $Fname=$2;
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

