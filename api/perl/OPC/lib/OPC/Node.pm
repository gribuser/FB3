# This class presents common functionality between package real parts (OPC::Part), and
# it's root (OPC::Root)
package OPC::Node;

use strict;
use warnings;
use Carp;

sub new {
	my( $Class, %Params ) = @_;

	if( !exists($Params{package}) || !defined( $Params{package} )) {
		Carp::confess 'Must specify package of the part in argument "package"';
	}
	my $Package = $Params{package};
	unless( $Package->isa( 'OPC' )) {
		Carp::confess 'Package must be instance of OPC';
	}

	if( !exists($Params{name}) || !defined( $Params{name} )) {
		Carp::confess 'Must specify name of the node in argument "name"';
	}
	my $Name = $Params{name};

	return bless {
		package => $Package,
		name => $Name,
	}, $Class;
}

sub Name { $_[0]->{name} }

sub Package { $_[0]->{package} }

sub RelatedPart {
	my( $self, %RelationParams ) = @_;

	my @Parts = $self->RelatedParts( %RelationParams );
	unless( @Parts ) {
		Carp::confess "No parts with given params found";
	}
	if( @Parts > 1 ) {
		Carp::confess "Requested only part with given params but found ".scalar(@Parts)." parts";
	}

	return @Parts ? $Parts[0] : undef;
}

sub RelatedParts {
	my( $self, %RelationParams ) = @_;

	return
		map $self->{package}->Part( name => $_->{TargetFullName} ),
		$self->Relations( %RelationParams );
}

sub Relations {
	my( $self, %RelationParams ) = @_;
	return $self->{package}->Relations( $self->RelsName, %RelationParams );
}

sub CreateRelationsID {
	my( $self, %RelationParams ) = @_;
	return $self->{package}->CreateRelationsID( $self->RelsName, %RelationParams );
}

sub RemoveRelations {
	my( $self, %RelationParams ) = @_;
  $self->{package}->RemoveRelations( $self->RelsName, %RelationParams );
}

sub AddRelation {
	my( $self, %RelationParams ) = @_;
  $self->{package}->AddRelation( $self->RelsName, %RelationParams );
}

sub RelsName {
	my $self = shift;
	unless( exists $self->{rels_name} ) {
		my $RelsName = $self->Name;
		$RelsName =~ s/^(.*)\/([^\/]*)$/$1\/\_rels\/$2\.rels/;
		unless( $self->Package->HasPart( $RelsName )) {
			Carp::confess 'Requested rels part for '.$self->Name.' doesn\'t exist';
		}
		$self->{rels_name} = $RelsName;
	}
	return $self->{rels_name};
}

sub RelsXML {
	my $self = shift;
	return $self->{package}->PartContents( $self->RelsName );
}

sub Content {
	my $self = shift;
	return $self->{package}->PartContents( $self->Name );
}

sub ContentType {
	my $self = shift;
	return $self->{package}->PartContentType( $self->Name );
}

1;
