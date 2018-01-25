use 5.014;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'FB3',
    license             => 'perl',
    dist_author         => q{www.litres.ru <gu@litres.ru>},
    dist_version_from   => 'lib/FB3.pm',
    dist_abstract       => 'API for manipulating FB3 files',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => '0',
    },
    build_requires => {
        'Test::More' => '0',
    },
    requires => {
        'perl' => 5.014, 
        'OPC' => 0,
        'XML::LibXML' => 0,
    },
    add_to_cleanup     => [ 'FB3-*' ],
);

$builder->create_build_script();
