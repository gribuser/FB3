use 5.014;
use strict;
use warnings;
use Module::Build;
use File::Fetch;
use File::Path;

mkdir 'share';
foreach (qw(fb3_descr_classes.xsd fb3_general.xsd fb3_relations.xsd opc-contentTypes.xsd opc-relationships.xsd dcterms.xsd dcmitype.xsd dc.xsd fb3_body.xsd fb3_descr.xsd fb3_links.xsd opc-coreProperties.xsd)) {
	File::Fetch->new(uri => 'http://github.com/gribuser/FB3/blob/master/'.$_)->fetch(to => 'share') or die 'Unable to get schema file '.$_;
}

my $Builder = Module::Build->new(
    module_name         => 'FB3',
    license             => 'lgpl',
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
        'perl'        => 5.014,
				'File::Fetch' => 0,
				'File::Path'  => 0,
        'OPC'         => 0,
        'XML::LibXML' => 0,
    },
		share_dir => {
			dist => 'share',
		},
    add_to_cleanup     => [ 'FB3-*' ],
);

$Builder->create_build_script();