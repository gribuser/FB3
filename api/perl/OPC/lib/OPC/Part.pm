package OPC::Part;

use strict;
use warnings;
use Carp;
use base 'OPC::Node';

sub new {
	my( $Class, %NodeParams ) = @_;

	my $Node = OPC::Node->new( %NodeParams );
	my $PartName = $Node->Name;
	unless( $Node->Package->HasPart( $PartName )) {
		Carp::confess "Part '$PartName' doesn't exist";
	}

	return bless $Node, $Class;
}

sub Content {
	my $self = shift;
	return $self->Package->PartContents( $self->Name );
}

sub SetContent {
	my ($self, $NewContents) = @_;
	$self->Package->SetContents( $self->Name, $NewContents );
}

sub PhysicalName {
	my $self = shift;
	return $self->Package->PhysicalNameByPartName( $self->Name );
}

1;
