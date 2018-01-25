use 5.014;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'FB3::Convert',
    license             => 'perl',
    dist_author         => q{www.litres.ru <gu@litres.ru>},
    dist_version_from   => 'lib/FB3/Convert.pm',
    dist_abstract       => 'scripts and API for converting FB3 from and to different formats',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => '0',
    },
    build_requires => {
        'Test::More' => '0',
    },
    requires => {
        'perl' => 5.014, 
        'FB3' => 0,
        'XML::LibXML' => 0,
        'XML::LibXSLT' => 0,
        'Archive::Zip' => 0,
        'Hash::Merge' => 0,
        'UUID::Tiny' => 0,
        'HTML::Entities' => 0,
        'Clone' => 0,
        'File::ShareDir' => 0,
    },
    script_files => [qw{
      bin/convert2fb3.pl
      bin/cutfb3.pl
      bin/fb3_to_fb2.pl
      bin/fb3_2_json.pl
      bin/importfb3_from_fb2.pl
    }],
    share_dir => 'share',
    add_to_cleanup     => [ 'FB3-Convert-*' ],
);

$builder->create_build_script();
