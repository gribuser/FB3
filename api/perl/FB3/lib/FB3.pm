package FB3;

use strict;
use warnings;
use utf8;
use OPC;
use Carp;

our $VERSION = '0.02';

use constant {
	RELATION_TYPE_CORE_PROP =>
		'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'
};

sub new {
	my( $Class, %Params ) = @_;

	my $OPCPackage;
	if( exists $Params{from_zip} && defined $Params{from_zip} ) {
		$OPCPackage = OPC->FromZip( $Params{from_zip} );

	} elsif( exists $Params{from_dir} && defined $Params{from_dir} ) {
		$OPCPackage = OPC->FromDir( $Params{from_dir} );

	} else {
		Carp::confess 'Must pass from_zip or from_dir argument';
	}

	my $self = {
    opc => $OPCPackage,
    root => $OPCPackage->Root,
  };

	return bless $self, $Class;
}

sub Cover {
	my $self = shift;
	return $self->{root}->Thumbnail;
}

sub Meta {
	my $self = shift;
	return $self->{root}->RelatedPart( type => 'http://www.fictionbook.org/FictionBook3/relationships/Book' );
}

sub Body {
	my $self = shift;
	return $self->Meta->RelatedPart( type => 'http://www.fictionbook.org/FictionBook3/relationships/body' ); 
}

sub Root {
  return shift->{root};
}

sub Part {
  my( $self, $PartName ) = @_;
  return $self->{opc}->Part( name => $PartName )
}

sub HasPart {
  my( $self, $PartName ) = @_;
  return $self->{opc}->HasPart( $PartName );
}

sub SetPartContents {
  my( $self, $PartName, $PartContents ) = @_;

  $self->{opc}->SetContents( $PartName, $PartContents );
}

sub DirPath {
  my $self = shift;
  if ($self->{opc}->{_is_zip}) {
    die "FB3 is ZIP archive, not directory";
  } else {
    return $self->{opc}->{_physical};
  }
}

1;
