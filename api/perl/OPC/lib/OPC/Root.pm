package OPC::Root;

use strict;
use warnings;
use Carp;
use base 'OPC::Node';

sub new {
	my( $Class, %NodeParams ) = @_;

	my $Node = OPC::Node->new( %NodeParams, name => '/' );

	return bless $Node, $Class;
}

sub Thumbnail {
	my $self = shift;
	return $self->RelatedPart( type => 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail' ); 
}

1;
