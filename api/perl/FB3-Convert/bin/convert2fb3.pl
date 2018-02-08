#!/usr/local/bin/perl

use strict;
use Getopt::Long;
use FB3::Convert;
use utf8;

my %OPT;
GetOptions(
  'verbose|v:1' => \$OPT{'verbose'},           
  'help|h' => \$OPT{'help'},
  'source|s=s' => \$OPT{'source'},
  'destination_dir|dd=s' => \$OPT{'dd'},
  'destination_file|df=s' => \$OPT{'df'},
  'metadata|md=s' => \$OPT{'md'},
  'validate|vl=s' => \$OPT{'vl'},
  'name|n:1' => \$OPT{'showname'},
  
  'meta_id=s' => \$OPT{'meta_id'},
  'meta_lang|meta_language=s' => \$OPT{'meta_lang'},
  'meta_title=s' => \$OPT{'meta_title'},
  'meta_annotation=s' => \$OPT{'meta_annotation'},
  'meta_genres=s' => \$OPT{'meta_genres'},
  'meta_authors=s' => \$OPT{'meta_authors'},
  'meta_date=s' => \$OPT{'meta_date'},
) || help();

$OPT{'source'} = $ARGV[0] unless $OPT{'source'};
$OPT{'df'} = $ARGV[1] unless $OPT{'ds'};

if ($OPT{'vl'}) {
  my $Obj = new FB3::Convert(empty=>1);
  my $Valid = $Obj->Validate($OPT{'vl'});
  print $Valid;
  exit;
}

unless ($OPT{'source'}) {
  print "\nsource file not defined\n";
  help();
}

my $Obj = new FB3::Convert(
  'source' => $OPT{'source'},
  'destination_dir' => $OPT{'dd'},
  'destination_file' => $OPT{'df'},
  'verbose' => $OPT{'verbose'},
  'metadata' => $OPT{'md'},
  'showname' => $OPT{'showname'},

  'meta' => {
    'id' => $OPT{'meta_id'},
    'language' => $OPT{'meta_lang'},
    'title' => $OPT{'meta_title'},
    'annotation' => $OPT{'meta_annotation'},
    'genres' => $OPT{'meta_genres'},
    'authors' => $OPT{'meta_authors'},
    'date' => $OPT{'meta_date'},
  },
);



$Obj->Reap();
my $FB3Path =  $Obj->FB3Create();
$Obj->Msg("FB3: ".$FB3Path." created\n","w");
my $Valid = $Obj->Validate();
print $Valid;
$Obj->FB3_2_Zip() if $OPT{'df'};
$Obj->Cleanup();

sub help {
  print <<_END
  
  USAGE: convert2fb3.pl --source|s= <input.file> [--verbose|v] [--help|h] [(--destination_dir|dd <dest.fb3>) | (--destination_file|df)]  [(--name|n)]
  
  --help : print this text
  --verbose : print processing status. Show parsing warnings if Verbose > 1
  --source : path to source file
  --destination_dir : path for non zipped fb3
  --destination_file :  path for zipped fb3
  --metadata : XML meta description file
  --name : show name of reaped epub file
  
  META:
  --meta_id
  --meta_lang
  --meta_title
  --meta_annotation
  --meta_date
  --meta_genres : can be ',' separated
  --meta_authors : "first middle last". full names can be ',' separated

_END
;
exit;
}
