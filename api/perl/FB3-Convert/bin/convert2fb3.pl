#!/usr/local/bin/perl

use strict;
use Getopt::Long;
use FB3;
use FB3::Convert;
use utf8;
use File::ShareDir qw/dist_dir/;

my %OPT;
GetOptions(
  'verbose|v:1' => \$OPT{'verbose'},           
  'help|h' => \$OPT{'help'},
  'source|s=s' => \$OPT{'source'},
  'src_type|st=s' => \$OPT{'src_type'},
  'destination_dir|dd=s' => \$OPT{'dd'},
  'destination_file|df=s' => \$OPT{'df'},
  'xsd=s'	=> \$OPT{xsd_dir},
  'metadata|md=s' => \$OPT{'md'},
  'validate|vl=s' => \$OPT{'vl'},
  'name|n:1' => \$OPT{'showname'},
  'b:1' => \$OPT{'b'},
  'bf:s' => \$OPT{'bf'},
  'phantomjs|phjs=s' => \$OPT{'phjs'},
  'euristic|e' => \$OPT{'eur'},
  'euristic_debug|ed=s' => \$OPT{'eur_deb'},

  'meta_id=s' => \$OPT{'meta_id'},
  'meta_lang|meta_language=s' => \$OPT{'meta_lang'},
  'meta_title=s' => \$OPT{'meta_title'},
  'meta_annotation=s' => \$OPT{'meta_annotation'},
  'meta_genres=s' => \$OPT{'meta_genres'},
  'meta_authors=s' => \$OPT{'meta_authors'},
  'meta_date=s' => \$OPT{'meta_date'},
) || help();

my $XsdPath = $OPT{xsd_dir} || FB3::SchemasDirPath();
my $XslPath = dist_dir('FB3-Convert');

if ($OPT{'vl'}) {
  my $Obj = new FB3::Convert(empty=>1);
  my $Valid = $Obj->Validate('path'=>$OPT{'vl'},'xsd'=>$XsdPath);
  print $Valid;
  exit;
}

$OPT{'source'} = $ARGV[0] unless $OPT{'source'};
$OPT{'df'} = $ARGV[1] unless $OPT{'df'};

my $FName = $OPT{'source'};
$FName =~ s/\.\w+$//;
$OPT{'df'} = $FName.'.fb3' if !$OPT{'dd'} && !$OPT{'df'};
$OPT{'bf'} = $FName.'.bench' if defined $OPT{'bf'} && !$OPT{'bf'};

unless ($OPT{'source'}) {
  print "\nsource file not defined\n";
  help();
}

my $Obj = new FB3::Convert(
  'source' => $OPT{'source'},
  'src_type' => $OPT{'src_type'},
  'destination_dir' => $OPT{'dd'},
  'destination_file' => $OPT{'df'},
  'verbose' => $OPT{'verbose'},
  'metadata' => $OPT{'md'},
  'showname' => $OPT{'showname'},
  'bench' => $OPT{'b'},
  'bench2file' => $OPT{'bf'},
  'phantom_js_path' => $OPT{'phjs'},
  'euristic' => $OPT{'eur'},
  'euristic_debug' => $OPT{'eur_deb'},
	'xsl_path' => $XslPath,

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

$Obj->_bs('ALL','Полная конвертация');

$Obj->Reap();

$Obj->_bs('fb3_create','Создание FB3 из данных, доводка до валидности');
my $FB3Path =  $Obj->FB3Create();
$Obj->_be('fb3_create');
$Obj->Msg("FB3: ".$FB3Path." created\n","w");

$Obj->_bs('validate_fb3','Валидация полученного FB3');
my $ValidErr = $Obj->Validate('xsd'=>$XsdPath);
$Obj->_be('validate_fb3');
print $ValidErr;

if ($OPT{'df'} && !$ValidErr) {
  $Obj->_bs('pack','Упаковка FB3 -> zip');
  $Obj->FB3_2_Zip();
  $Obj->_be('pack');
}

$Obj->_bs('cleanup','Сборка мусора');
$Obj->Cleanup($ValidErr?1:0);
$Obj->_be('cleanup');

$Obj->_be('ALL');

$Obj->_bf();

sub help {
  print <<_END
  
  USAGE: convert2fb3.pl --source|s= <input.file> [--verbose|v] [--help|h] [(--destination_dir|dd <dest.fb3>) | (--destination_file|df)] [--src_type|st] [(--name|n)] [--validate|vl=] [--euristic|e] [--euristic_debug|ed] [--phantomjs|phjs]
  
  --help : print this text
  --verbose : print processing status. Show parsing warnings if Verbose > 1
  --src_type : source format (fb2|epub)
  --source : path to source file
  --destination_dir : path for non zipped fb3
  --destination_file :  path for zipped fb3
  --metadata : XML meta description file
  --name : show name of reaped epub file
  --validate : don't convert, only validate fb3 file from path
  --euristic : try euristic analize for detect strange titles
  --euristic_debug : path to dir for euristica debug
  --phantomjs|phjs : path to binary 'phantomjs'. Must be installed for euristica analize titles <http://phantomjs.org/> (with --e opt)

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
