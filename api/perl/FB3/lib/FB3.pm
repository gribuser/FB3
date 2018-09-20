package FB3;

use strict;
use warnings;
use utf8;
use OPC;
use Carp;
use File::ShareDir qw/dist_dir/;

our $VERSION = '0.08';

=head1 NAME

FB3 - API for manipulating FB3 files

=head1 SYNOPSIS

  use FB3;

  # load FB3 from file
  my $FB3 = FB3->new( from_zip => 'path/to/file.fb3');

  # or load FB3 from directory where it had been unpacked
  my $FB3 = FB3->new( from_dir => 'path/to/unpacked_fb3_dir');

  # navigate through FB3 and read XML content of it's main parts
  $Meta = $FB3->Meta;
  $MetaXML = $Meta->Content;
  $BodyXML = $FB3->Body->Content;

  # get path to cover
  $PathToCover = $FB3->Cover->PhysicalName;

=head1 AUTHOR

Litres.ru Team

=cut

use constant {
	RELATION_TYPE_CORE_PROP =>
		'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'
};

# Returns path to FB3 schemas common directory
sub SchemasDirPath {
  return dist_dir('FB3');
}

# Returns path to requested FB3 scheme
sub SchemaPath {
  my $SchemaName = shift;
  my $SchemaPath = FB3::SchemasDirPath().'/'.$SchemaName;
  die "$SchemaName doesn't exist" unless -e $SchemaPath;
  return $SchemaPath;
}

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

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018 Litres.ru

The GNU Lesser General Public License version 3.0

FB3 is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3.0 of the License.

FB3 is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public
License for more details.

Full text of License L<http://www.gnu.org/licenses/lgpl-3.0.en.html>.

=cut

1;
