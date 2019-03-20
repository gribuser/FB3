package OPC;

use strict;
use feature 'say';
use utf8;
use Carp;
use File::Find;
use File::Basename;
use File::Copy;
use Cwd;
use Encode;
use Archive::Zip qw/ :ERROR_CODES :CONSTANTS /;
use XML::LibXML;
use OPC::Root;
use OPC::Part;

our $VERSION = '0.05';

=head1 NAME

OPC - API for low-level manipulations with packages in OPC format (ECMA-376 Part 2)

=head1 SYNOPSIS

  my $Package = eval{ OPC->new( '/path/to/opc/package' ) };
  if( $@ ) {
    die "/path/to/opc/package is not a valid OPC package: $@";
  }

  # Get part by name
  my $Part1 = $Package->Part(name => '/part/name');

  # Get root node
  my $Root = $Package->Root;

  # Get package related part with C<Type> 'http://my.own/custom/type'
  my $Part2 = $Root->RelatedPart(type => 'http://my.own/custom/type');

  # Get list of parts related to some other part
  my @PictureParts = $Part2>RelatedParts(type => 'http://my.own/type/for/pictures');

=head1 DESCRIPTION

See http://www.ecma-international.org/publications/standards/Ecma-376.htm

=head1 AUTHOR

Litres.ru Team
=cut

my $XC = XML::LibXML::XPathContext->new();
my %FB3Namespaces = (
  opcr => 'http://schemas.openxmlformats.org/package/2006/relationships',
	opcct => 'http://schemas.openxmlformats.org/package/2006/content-types',
);
$XC->registerNs( $_ => $FB3Namespaces{$_} ) for keys %FB3Namespaces;

sub new {
  my( $Class, $PackagePath ) = @_;

	if( -d $PackagePath ) {
		# Got path to directory. That means it's unpacked OPC
		return $Class->FromDir( $PackagePath );
	} elsif( -f $PackagePath ) {
		# Got path to file. Probably that means it's zipped OPC
		return $Class->FromZip( $PackagePath );
	} else {
		Carp::confess "Must specify path to zip package or directory. Path=[$PackagePath]";
	}
}

sub FromZip {
  my( $Class, $ZipFilePath ) = @_;

  my $Zip = Archive::Zip->new();
  my $ReadStatus = $Zip->read( $ZipFilePath );
  unless( $ReadStatus == AZ_OK ) {
    die $ReadStatus == AZ_FORMAT_ERROR ? "$ZipFilePath is not a valid ZIP archive" :
                                         "Failed to open ZIP archive $ZipFilePath";
  }

  # Проверка правильности метода сжатия (deflated или stored)

  for my $Member ( $Zip->members ) {
    unless( grep $Member->compressionMethod == $_, COMPRESSION_STORED,
        COMPRESSION_DEFLATED ) {

      die 'Item "'. $Member->fileName .'" uses unsupported compression method. '.
        'Need "stored" or "deflated"';
    }
  }

  my( $ZipMemberNameByPartName, $PartNames );
  ZIP_MEMBER_NAME: for my $ZipMemberName ( $Zip->memberNames ) {

    # Пытаемся получить имя части по имени элемента ZIP архива

    my $PartName = do {
      use bytes; # чтобы lc действовал только на ASCII
      lc "/$ZipMemberName";
    };

    # Если получившееся имя части не соответствует правилам, то пропускаем такой элемент

    # Выполняем последнюю проверку на неэквивалетность ранее прочитанным именам частей
    # и, если всё в порядке, запоминаем полученное имя части

    if( grep $PartName eq $_, @$PartNames ) {
      # найдены части с эквивалетным названием. Согласно [M1.12] такого быть не должно
      die "There several zip items with part name '$PartName' (OPC M1.12 violation)";
    } else {
      push @$PartNames, $PartName;
      $ZipMemberNameByPartName->{ $PartName } = $ZipMemberName;
    }
  }

  return bless({
		_is_zip => 1,
    _physical => $Zip,
    _physical_name_by_part_name => $ZipMemberNameByPartName,
    _part_names => $PartNames,
  }, $Class );
}

sub FromDir {
	my( $Class, $DirPath ) = @_;
	if( !defined($DirPath) || !-d $DirPath ) {
		Carp::confess 'Directory doesn\'nt exist';
	}
	$DirPath = Cwd::abs_path( $DirPath );
	# delete trailing slash from directory name
	$DirPath =~ s/\/$//g;
	my $DirPathLength = length( $DirPath );

  my( $PhysicalNameByPartName, $PartNames );
	File::Find::find( sub{
		if( -f ) {
			my $PartName = $File::Find::name;
			$PartName = substr $PartName, $DirPathLength; # delete directory name from part name

			my $PartName = do {
				use bytes; # for lc to be applied only to ASCII symbols
				lc $PartName;
			};

			push @$PartNames, $PartName;
			$PhysicalNameByPartName->{$PartName} = $File::Find::name;
		}
	}, $DirPath );
  return bless({
		_is_zip => 0,
    _physical => $DirPath,
    _physical_name_by_part_name => $PhysicalNameByPartName,
    _part_names => $PartNames,
  }, $Class );
}

sub GetPhysicalContents {
	my( $self, $PhysicalName, %Param ) = @_;
  my $IsBinary = exists $Param{binary} ? $Param{binary} : 0;
  
	if( $self->{_is_zip} ) {
		return scalar $self->{_physical}->contents( $PhysicalName );
	} else {
		return do {
      my $Layer = $IsBinary ? 'raw' : 'encoding(UTF-8)';
      open my $fh, "<:$Layer", $PhysicalName;
			local $/;
			<$fh>;
		}
	}
}

sub SetPhysicalContents {
	my( $self, $PhysicalName, $NewContents, %Param ) = @_;
  my $IsBinary = exists $Param{binary} ? $Param{binary} : 0;

	if( $self->{_is_zip} ) {
		$self->{_physical}->contents( $PhysicalName, $NewContents );

	} else {
    my $IsFileHandle = (ref($NewContents)
       ? (ref($NewContents) eq 'GLOB'
          || UNIVERSAL::isa($NewContents, 'GLOB')
                            || UNIVERSAL::isa($NewContents, 'IO::Handle'))
       : (ref(\$NewContents) eq 'GLOB'));

    if( $IsFileHandle ) {
      # new contents was given as file handle (prefered way)
      File::Copy::copy $NewContents, $PhysicalName
        or die "Can't update contents of $PhysicalName: $!";

    } else {
      # new contents was given as string
      my $Layer = $IsBinary ? 'raw' : 'encoding(UTF-8)';
      open my $fh, ">:$Layer", $PhysicalName
        or die "Can't open $PhysicalName for writing: $!";
      print {$fh} $NewContents
        or die "Can't update contents of $PhysicalName: $!";
    }
	}
}

sub GetContentTypesXML {
  my( $self ) = @_;

	my $PhysicalName = $self->{_is_zip}
		? '[Content_Types].xml'
		: $self->{_physical}.'/'.'[Content_Types].xml';
		
  return $self->GetPhysicalContents( $PhysicalName );
}

sub PartContents {
  my( $self, $PartName ) = @_;
	my $PhysicalName = $self->PhysicalNameByPartName( $PartName );
  if( $PhysicalName ) {
    my $IsBinary = $self->IsBinary($PartName);
    return $self->GetPhysicalContents( $PhysicalName, binary => $IsBinary );
  }
  return undef;
}

sub IsBinary {
  my ($self, $PartName) = @_;
  my $ContentType = $self->PartContentType( $PartName );
  if( grep $ContentType eq $_, 'image/png', 'image/jpeg', 'image/gif' ) {
    return 1;
  }
  return 0;
}

sub SetContents {
  my( $self, $PartName, $NewContents ) = @_;
	my $PhysicalName = $self->PhysicalNameByPartName( $PartName );

  # there is no part with such a name - let's create one
  unless( $PhysicalName ) {
    # first check part name doesn't include . or .. - here we need only full part names
    die "Can't set part contents. Name '$PartName' includes . or .."
      if $PartName =~ /(^|\/)(.|..)(\/|$)/;

    # then correct part name
    $PartName = do {
      use bytes; # for lc to only affect ASCII symbols
      lc $PartName;
    };

    # creating physical part name
    if( $self->{_is_zip} ) {
      ( $PhysicalName = $PartName ) =~ s:^\/::; # removing leading slash
    } else {
      $PhysicalName = $self->{_physical}.$PartName;

      # ensure related directory exists
      my $DirectoryName = File::Basename::dirname( $PartName );
      unless( -d $self->{_physical}.$DirectoryName ) {
        my $CurPath = $self->{_physical};
        for (split /[\\\/]/,$DirectoryName){
          $CurPath.="$_";
          unless (-d $CurPath){
            mkdir $CurPath || die "$CurPath: $!";
          }
          $CurPath.='/';
        }
      }
    }
    push @{$self->{_part_names}}, $PartName;
    $self->{_physical_name_by_part_name}->{$PartName} = $PhysicalName;
  }

  my $IsBinary = $self->IsBinary($PartName);
  $self->SetPhysicalContents( $PhysicalName, $NewContents, binary => $IsBinary );
}

sub PartContentType {
	my( $self, $PartName ) = @_;

  $PartName = do {
    use bytes; # A-Za-z are case insensitive
    lc $PartName;
  };

	unless( exists $self->{_content_type_by_part_name} ) {
    my $CtXML = $self->GetContentTypesXML;
    unless( $CtXML ) {
      Carp::confess "Content Types part not found";
    }
		my $CtDoc = XML::LibXML->new()->parse_string( $CtXML );

    use bytes; # case insensitive a-zA-Z

    my %CtByExtension =
      map { lc( $_->getAttribute('Extension') ) => $_->getAttribute('ContentType') }
      $XC->findnodes( '/opcct:Types/opcct:Default', $CtDoc );

    my %CtByPartName =
      map { lc( $_->getAttribute('PartName') ) => $_->getAttribute('ContentType') }
      $XC->findnodes( '/opcct:Types/opcct:Override', $CtDoc );

    no bytes;

		$self->{_content_type_by_part_name} = {};

		for my $EachPartName ( $self->PartNames ) {
			$EachPartName =~ /\.([^.]+)$/;
			my $Extension = $1;
			if( defined $CtByPartName{ $EachPartName } ) {
				$self->{_content_type_by_part_name}->{$EachPartName} = $CtByPartName{ $EachPartName };
			} else {
				$self->{_content_type_by_part_name}->{$EachPartName} = $CtByExtension{ $Extension };
			}
		}
	}

	return $self->{_content_type_by_part_name}->{$PartName};
}

sub PhysicalNameByPartName {
  my( $self, $PartName ) = @_;

  $PartName = do {
    use bytes; # A-Za-z are case insensitive
    lc $PartName;
  };

  return
		exists $self->{_physical_name_by_part_name}->{$PartName}
		? $self->{_physical_name_by_part_name}->{$PartName}
		: undef;
}

# DEPRECATED: alias for compatibility
sub ZipMemberNameByPartName { return PhysicalNameByPartName( @_ ) }

sub PartNames {
  my( $self ) = @_;
  return @{ $self->{_part_names} };
}

sub HasPart {
	my( $self, $PartName ) = @_;
	
	# Check part existense by existense in physical package
	return defined $self->PhysicalNameByPartName( $PartName );
}

# Retrieve relations from rels file (can retrieve relations by type of by id)
sub Relations {
	my( $self, $RelsPartName, %RelationParams ) = @_;

  my $Xml = $self->PartContents( $RelsPartName );

	# Get list of relation nodes
	my $RelsDoc = XML::LibXML->load_xml( string => $Xml );

	my @RelationNodes = $self->RelationNodesFromDoc( $RelsDoc, %RelationParams );

	my @Relations;
	for my $RelationNode ( @RelationNodes ) {
		my %Relation = map { $_ => $RelationNode->getAttribute($_) } 'Id', 'Target', 'Type';

		# Calculate target absolute path
		my( $Source ) = ( split '_rels/', $RelsPartName );
		$Relation{TargetFullName} = FullPartNameFromRelative( $Relation{Target}, $Source );

		push @Relations, \%Relation;
	}
	return @Relations;
}

sub RemoveRelations {
	my( $self, $RelsPartName, %RelationParams ) = @_;

	# Get list of relation nodes for removement
	my $RelsDoc = XML::LibXML->load_xml( string => $self->PartContents( $RelsPartName ));
	my @RelationNodes = $self->RelationNodesFromDoc( $RelsDoc, %RelationParams );

  # Remove if there is something to remove. Otherwise just feel fine
  if( @RelationNodes ) {
    my( $RelsRoot ) = $XC->findnodes( '/opcr:Relationships', $RelsDoc );

    for my $RelationNode ( @RelationNodes ) {
      $RelsRoot->removeChild( $RelationNode );
    }

    # update contents in file
    my $RelsXML = Encode::decode_utf8( $RelsDoc->toString );
    $self->SetContents( $RelsPartName, $RelsXML );
  }
}

sub AddRelation {
	my( $self, $RelsPartName, %RelationParams ) = @_;

	my $RelsDoc = XML::LibXML->load_xml( string => $self->PartContents( $RelsPartName ));
  my( $RelsRoot ) = $XC->findnodes( '/opcr:Relationships', $RelsDoc );

  my $NewRelationNode = $RelsDoc->createElement( 'Relationship' );
  $NewRelationNode->setAttribute( Type => $RelationParams{type} ) if $RelationParams{type};
  $NewRelationNode->setAttribute( Target => $RelationParams{target} ) if $RelationParams{target};

  my @ExistingRelationIDs =
    map $_->nodeValue,
    $XC->findnodes( 'opcr:Relationship/@Id', $RelsRoot );

  my $RelationID;
  if( $RelationParams{id} ) {
    $RelationID = $RelationParams{id};

    if( grep $RelationID eq $_, @ExistingRelationIDs ) {
      die "Can't add relation to $RelsPartName. Id '$RelationID' already exists"
    }

  } else {

    my $i = 1;
    while( 1 ) {
      $RelationID = "rId$i";
      last unless grep $RelationID eq $_, @ExistingRelationIDs;
      $i++;
    }
  }
  $NewRelationNode->setAttribute( Id => $RelationID );

  $RelsRoot->appendChild( $NewRelationNode );

  # update contents in file
  my $RelsXML = Encode::decode_utf8( $RelsDoc->toString );
  $self->SetContents( $RelsPartName, $RelsXML );
}

sub CreateRelationsID {
  my ( $self, $RelsPartName, %RelationParams ) = @_;
  my $RelationID;

  my $RelsDoc = XML::LibXML->load_xml( string => $self->PartContents( $RelsPartName ));
  my ( $RelsRoot ) = $XC->findnodes( '/opcr:Relationships', $RelsDoc );

  my @ExistingRelationIDs =
    map $_->nodeValue,
      $XC->findnodes( 'opcr:Relationship/@Id', $RelsRoot );

  my $i = 1;
  while( 1 ) {
    $RelationID = "rId$i";
    last unless grep $RelationID eq $_, @ExistingRelationIDs;
    $i++;
  }

  return $RelationID;
}

# Supplementary method: return relations nodes with given parameters
sub RelationNodesFromDoc {
	my( $self, $RelsDoc, %RelationParams ) = @_;

  if( !$RelationParams{id} && !$RelationParams{type} ) {
		Carp::confess 'No relation parameters given';
	}

	my $Filter;
	if( $RelationParams{type} ) {
		$Filter = '@Type="'.$RelationParams{type}.'"';
	}

  if( $RelationParams{id} ) {
		$Filter = '@Id="'.$RelationParams{id}.'"';
	}

	return $XC->findnodes(
		"/opcr:Relationships/opcr:Relationship[$Filter]",
		$RelsDoc );
}

# Retrieve relations by type and return list of hashref
sub RelationsByType {
	my( $self, $RelsPartName, $RelType ) = @_;
	return $self->Relations( $RelsPartName, type => $RelType );
}

# Извлекает связь заданного типа из rels части, что связь данного типа только одна,
# иначе выбрасывает фатальную ошибку
# Don't use RelationByType with $GetMulty param, use RelationsByType method instead
sub RelationByType {
	my( $self, $RelsPartName, $RelType, $GetMulty ) = @_;

	my @Relations = $self->RelationsByType( $RelsPartName, $RelType );
	if( !$GetMulty && @Relations > 1 ) {
		die "Expected only one relation of type $RelType in $RelsPartName but found several";
	}
	
  if ($GetMulty) {
    return @Relations;
  } elsif (@Relations) {
    return %{$Relations[0]};
  } else {
    return ();
  }
}

# вспомогательная функция: получить полное имя части по относительной ссылке на неё
# и имени части, относительно которой ищем
sub FullPartNameFromRelative {
  my $Name = shift;
  my $Dir = shift;
  $Dir =~ s:/$::; # remove trailing slash

  my $FullName = ( $Name =~ m:^/: ) ? $Name :       # в $Name - полный путь
                                      "$Dir/$Name"; # в $Name - относительная ссылка

  $FullName =~ s:^/::; # remove leading slash

  $FullName = do{
    use bytes; # A-Za-z are case insensitive
    lc $FullName;
  };

  # обрабатываем все . и .. в имени
  my @CleanedSegments;
  my @OriginalSegments = split m:/:, $FullName;
  for my $Part ( @OriginalSegments ) {
    if( $Part eq '.' ) {
      # просто пропускаем
    } elsif( $Part eq '..' ) {
      if( @CleanedSegments > 0 ) {
        pop @CleanedSegments;
      } else {
        die "/$FullName part name is invalid, because it's pointing out of FB3 root";
      }
    } else {
      push @CleanedSegments, $Part;
    }
  }

  return '/'.( join '/', @CleanedSegments );
}

sub Root {
	my $self = shift;

	return OPC::Root->new( package => $self );
}

sub Part {
	my( $self, %Params ) = @_;
	my $PartName = $Params{name};

	return OPC::Part->new( package => $self, name => $PartName )
}

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018 Litres.ru

The GNU Lesser General Public License version 3.0

OPC is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3.0 of the License.

OPC is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public
License for more details.

Full text of License L<http://www.gnu.org/licenses/lgpl-3.0.en.html>.

=cut

1;
