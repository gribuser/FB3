use 5.014;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'FB3::Convert',
    license             => 'lgpl',
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
        'FB3' => 0.13,
        'XML::LibXML' => 0,
        'XML::LibXSLT' => 0,
        'Archive::Zip' => 0,
        'Hash::Merge' => 0,
        'UUID::Tiny' => 0,
        'WWW::Mechanize::PhantomJS' => 0,
        'XML::Entities' => 0,
        'XML::Entities::Data' => 0,
        'Clone' => 0,
        'File::ShareDir' => 0,
        'XML::Diff' => 0,
        'Image::Info' => 0,
        'JSON::Path' => 0,
        'Image::Size' => 0,
        'Image::ExifTool' => 0,
        'URI::Escape' => 0,
        'Lingua::Identify' => 0,
        'Image::Magick' => 0,
        'TeX::Hyphen' => 0,
    },
    script_files => [qw{
      bin/convert2fb3.pl
      bin/cutfb3.pl
      bin/fb3_to_fb2.pl
      bin/fb3_2_json.pl
    }],
    share_dir => {
			dist => [ 'share', 't/examples' ]
		},
    add_to_cleanup     => [ 'FB3-Convert-*' ],
);

$builder->create_build_script();
