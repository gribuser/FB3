package FB3::OPCNavigator;
use strict;

=pod
my $Package = eval{ FB3::OPCNavigator->new( '/path/to/opc/package' ) };
if( $@ ) {
  die "/path/to/opc/package is not a valid OPC package: $@";
}

my $PartContents = $Package->PartContents( '/part/name' );
my @AllPartNames = $Package->PartNames;
my %Relation = $Package->RelationByType( '/_rels/.rels', 'http://my.own/custom/type' ); 
my $PartName = $Relation{TargetFullName};
=cut

use Archive::Zip qw/ :ERROR_CODES :CONSTANTS /;
use XML::LibXML;

my $XC = XML::LibXML::XPathContext->new();
my %FB3Namespaces = (
  opcr => 'http://schemas.openxmlformats.org/package/2006/relationships',
);
$XC->registerNs( $_ => $FB3Namespaces{$_} ) for keys %FB3Namespaces;

sub new {
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

    # "A part URI shall not have a forward slash as the last character. [M1.5]"
    next if $PartName =~ /\/$/;

    # Проверяем отдельные сегменты имени
    for my $NameSegment ( split '/', $PartName ) {

      # "A segment shall not contain percent-encoded forward slash (“/”), or backward
      # slash (“\”) characters. [M1.7]"
      # "A segment shall not contain percent-encoded unreserved characters. [M1.8]"
      for my $Char (( '/', '\\', 'a'..'z', 0..9, '-', '.', '_', '~' )) {
        my $PercentEncodedChar = sprintf( '%%%x', ord( $Char ));
        next ZIP_MEMBER_NAME if $NameSegment =~ /$PercentEncodedChar/i; 
      }

      # "A segment shall not end with a dot (“.”) character. [M1.9]"
      next ZIP_MEMBER_NAME if $NameSegment =~ /\.$/;

      # "A segment shall include at least one non-dot character. [M1.10]"
      # (избыточное условие, удовлетворяющееся с помощью M1.9)
    }

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
    _zip => $Zip,
    _zip_member_name_by_part_name => $ZipMemberNameByPartName,
    _part_names => $PartNames,
  }, $Class );
}

sub GetContentTypesXML {
  my( $self ) = @_;
  return $self->{_zip}->contents( '[Content_Types].xml' );
}

sub PartContents {
  my( $self, $PartName ) = @_;
  return $self->{_zip}->contents( $self->ZipMemberNameByPartName( $PartName ));
}

sub ZipMemberNameByPartName {
  my( $self, $PartName ) = @_;

  $PartName = do {
    use bytes; # A-Za-z are case insensitive
    lc $PartName;
  };

  return $self->{_zip_member_name_by_part_name}->{$PartName};
}

sub PartNames {
  my( $self ) = @_;
  return @{ $self->{_part_names} };
}

# Извлекает связь заданного типа из rels части
# Рассчитывает, что связь данного типа только одна, иначе выбрасывает фатальную ошибку
sub RelationByType {
	my( $self, $RelsPartName, $RelType ) = @_;

	# получаем ссылку переданного типа
	my $RelsDoc = XML::LibXML->load_xml( string => $self->PartContents( $RelsPartName ));
	my @RelationNodes = $XC->findnodes(
		'/opcr:Relationships/opcr:Relationship[@Type="'.$RelType.'"]',
		$RelsDoc );
	if( @RelationNodes > 1 ) {
		die "Запрошенному типу $RelType соответствует несколько связей, а должна ".
			"соответствовать только одна";
	}
	
	my %Relation;
	if( @RelationNodes ) {
		%Relation = map { $_ => $RelationNodes[0]->getAttribute($_) } 'Id', 'Target', 'Type';

		# получаем имя части, относительно которой задана ссылка
		my( $Source ) = ( split '_rels/', $RelsPartName );
		$Relation{TargetFullName} = FullPartNameFromRelative( $Relation{Target}, $Source );
	}
	return %Relation;
}

# вспомогательная функция: получить полное имя части по относительной ссылке на неё
# и имени части, относительно которой ищем
sub FullPartNameFromRelative {
  my $Name = shift;
  my $Dir = shift;
  $Dir =~ s:/$::; # убираем последний слэш

  my $FullName = ( $Name =~ m:^/: ) ? $Name :       # в $Name - полный путь
                                      "$Dir/$Name"; # в $Name - относительная ссылка
  my $FullName = do{
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
      pop @CleanedSegments;
    } else {
      push @CleanedSegments, $Part;
    }
  }

  return join '/', @CleanedSegments;
}

1;
