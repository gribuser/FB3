use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'OPC',
    license             => 'lgpl',
    dist_author         => q{www.litres.ru <gu@litres.ru>},
    dist_version_from   => 'lib/OPC.pm',
    dist_abstract       => 'API for low-level manipulations with packages in OPC format (ECMA-376 Part 2)',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => '0',
    },
    build_requires => {
        'Test::More' => '0',
    },
    requires => {
        'perl' => 5.014, 
        'XML::LibXML' => 0,
        'Archive::Zip' => 0,
    },
    add_to_cleanup     => [ 'OPC-*' ],
);

$builder->create_build_script();
