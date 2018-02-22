use 5.014;
use strict;
use warnings;
use Module::Build;
use File::Fetch;
use File::Path;
use File::Copy;

my $XSDFound = 0;
my @XSDFiles = (qw(fb3_descr_classes.xsd fb3_general.xsd fb3_relations.xsd opc-contentTypes.xsd opc-relationships.xsd dcterms.xsd dcmitype.xsd dc.xsd fb3_body.xsd fb3_descr.xsd fb3_links.xsd opc-coreProperties.xsd));
if (-d 'share') {
	foreach (@XSDFiles) {
		unless (-e 'share/'.$_) {
			rmtree('share');
			die 'Unable to get schema file '.$_;
			$XSDFound = 0;
			last;
		} else {
			$XSDFound = 1;
		}
	}
}
unless ($XSDFound) {
	mkdir 'share';
	my $LocalXSDDir = '../../../';
	foreach (@XSDFiles) {
		if (-e $LocalXSDDir.$_) {
			copy($LocalXSDDir.$_, 'share/'.$_);
			$XSDFound = 1;
		} else {
			$XSDFound = 0;
			rmtree('share');
			last;
		}
	}
}
unless ($XSDFound) {
	mkdir 'share';
	foreach (@XSDFiles) {
		unless (File::Fetch->new(uri => 'http://github.com/gribuser/FB3/blob/master/'.$_)->fetch(to => 'share')) {
			$XSDFound = 0;
			rmtree('share');
			last;
		} else {
			$XSDFound = 1;
		}
	}
}


die 'Unable to get schema files' unless $XSDFound;
	
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
				'File::Copy'  => 0,
        'OPC'         => 0,
        'XML::LibXML' => 0,
    },
		share_dir => {
			dist => 'share',
		},
    add_to_cleanup     => [ 'FB3-*' ],
);

$Builder->create_build_script();
