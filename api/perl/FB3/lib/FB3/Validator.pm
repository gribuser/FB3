package FB3::Validator;

=head1 NAME

FB3::Validator - check file to be a valid FB3 book

=head1 SYNOPSIS

  my $Validator = FB3::Validator->new;
  if( my $ValidationError = $Validator->Validate( "path/to/book.fb3" )) {
    die "path/to/book.fb3 is not a valid FB3: $ValidationError";
  }

=cut

use strict;
use OPC;
use XML::LibXML;
use FB3;

our $XSD_DIR;

use constant {
  RELATION_TYPE_CORE_PROPERTIES =>
    'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
  RELATION_TYPE_FB3_BOOK =>
    'http://www.fictionbook.org/FictionBook3/relationships/Book',
  RELATION_TYPE_FB3_BODY =>
    'http://www.fictionbook.org/FictionBook3/relationships/body',
};

use constant {
  CORE_PROPERTIES_CT => 'application/vnd.openxmlformats-package.core-properties+xml',
  RELATIONSHIPS_CT => 'application/vnd.openxmlformats-package.relationships+xml',
};

sub new {
  my( $class, $XSD_DIR ) = @_;
  $XSD_DIR //= FB3::SchemasDirPath(); # in development purposes it maybe
    # convenient to use some other schemas path

  my $Validator = {
    xsd_dir => $XSD_DIR,
  };
  
  bless $Validator, $class;

  return $Validator;
}

# Возвращает пустую строку в случае успеха, иначе - текст ошибки
sub Validate {
  my( $self, $FileName ) = @_;

  my $XSD_DIR = $self->{xsd_dir};

  # Проверка, что файл - валидный ZIP архив

  my $Package = eval{ OPC->new( $FileName ) };
  return $@ if( $@ );

  my %Namespaces = (
    opcr => 'http://schemas.openxmlformats.org/package/2006/relationships',
  );
  my $XPC = XML::LibXML::XPathContext->new();
  $XPC->registerNs( $_ => $Namespaces{$_} ) for keys %Namespaces;

  # Находим Content Types Stream, проверяем валидность

	my $CtXML = $Package->GetContentTypesXML;
	unless( $CtXML ) {
		return "Content Types part not found";
	}
	my $CtSchema = XML::LibXML::Schema->new( location =>
		"$XSD_DIR/opc-contentTypes.xsd" );
	my $CtDoc;
	eval {
		$CtDoc = XML::LibXML->new()->parse_string( $CtXML );
		$CtSchema->validate( $CtDoc );
	};
	if( $@ ) {
		return "Content Types part contains invalid XML or is invalid against ".
			"XSD schema:\n$@";
	}

  # Находим все части, описывающие связи (Relationships).

	my @ValidPartNames = grep IsValidPartName($_), $Package->PartNames;

  my @RelsPartNames;
  for my $PartName ( @ValidPartNames ) {
		my( $SourceDir, $SourceFileName ) = _SourceByRelsPartName( $PartName );
		if( defined $SourceDir && defined $SourceFileName ) {
			my $SourcePartName = $SourceDir.$SourceFileName;

			if( $SourcePartName eq "/"  # источник - сам архив
					|| grep $SourcePartName eq $_, @ValidPartNames  # источник есть в архиве
					) {

				push @RelsPartNames, $PartName unless grep $PartName eq $_, @RelsPartNames;
			}
		}
  }

  # Проверки частей, описывающих связи

  my $PackageRelsDoc; # заодно находим часть с Package Relationships
  my @PartNames; # заодно собираем названия всех частей, связи с которыми прописаны

  my $RelsSchema = XML::LibXML::Schema->new( location => "$XSD_DIR/opc-relationships.xsd" );

  for my $RelsPartName ( @RelsPartNames ) {

    # Проверка части на соответствие opc-relationships.xsd

    my $RelsDoc;
    my $RelsPartXML = $Package->PartContents( $RelsPartName );
    eval {
      $RelsDoc = XML::LibXML->new()->parse_string( $RelsPartXML );
      $RelsSchema->validate( $RelsDoc );
    };
    if( $@ ) {
      return $RelsPartName." is not a valid XML or is not valid against ".
        "opc-relationships.xsd:\n$@";
    }

    # У Relationships частей должен быть соответствующий Content Type

    unless( $Package->PartContentType( $RelsPartName ) eq RELATIONSHIPS_CT ) {
      return "Wrong content type for $RelsPartName (OPC M1.30 violation)"
    }

    # Проверки отдельных связей

    my( $SourceDir ) = _SourceByRelsPartName( $RelsPartName );
    my @RelIDs;
    for my $RelNode ( $XPC->findnodes( '/opcr:Relationships/opcr:Relationship',
        $RelsDoc )) {

      # У связей должен быть уникальный ID

      my $RelID = $RelNode->getAttribute('Id');
      if( grep $RelID eq $_, @RelIDs ) {
        return "Duplicate Ids in Relationships part $RelsPartName ".
          "(OPC M1.26 violation)";
      }

      my $TargetMode = $RelNode->getAttribute('TargetMode') || 'Internal';
      if( $TargetMode eq 'Internal' ) {

        # Части, связи с которыми описаны, должны существовать

        my $RelatedPartName = OPC::FullPartNameFromRelative(
          $RelNode->getAttribute('Target'), $SourceDir );

        unless( grep $RelatedPartName eq $_, @ValidPartNames ) {
          return "$RelsPartName contains reference on unexisting part $RelatedPartName";
        }

        # Не должно быть связей с другими Relationships частями [M1.25]

        if( grep $RelatedPartName eq $_, @RelsPartNames ) {
          return "Relationship part $RelsPartName contains reference on another ".
            "Relationships part $RelatedPartName (OPC M1.25 violation)";
        }

        push @PartNames, $RelatedPartName
          unless grep $RelatedPartName eq $_, @PartNames;
      }
    }

    if( $RelsPartName eq "/_rels/.rels" ) {
      $PackageRelsDoc = $RelsDoc;
    }
  }

  # Общие для всех частей проверки

  for my $PartName ( @PartNames ) {

    # У всех частей должен быть задан Content type [M1.2], хотя он может быть
    # пустым [M1.14]

    unless( defined $Package->PartContentType( $PartName )) {
      return "Content type is not provided for $PartName (OPC M1.2 violation)";
    }
  }
  
  # Обязательно должна быть часть, описывающая связи пакета (/_rels/.rels)

  unless( $PackageRelsDoc ) {
    return "Can't find package relationships item (/_rels/.rels)";
  }

  # В пакете может присутствовать максимум одна часть, описывающей мета данные
  # (Core Properties) [M4.1]

  my @CorePropRelations = $XPC->findnodes(
    '/opcr:Relationships/opcr:Relationship[@Type="'.RELATION_TYPE_CORE_PROPERTIES.'"]',
    $PackageRelsDoc );

  if( @CorePropRelations > 1 ) {
    return "Found more than one part with type 'Core Properties' (OPC M4.1 violation)";
  }

  # Если такая часть есть - проверка XML валидности, соответствия схеме и content type
  
  if( @CorePropRelations ) {
    my $CorePropPartName = OPC::FullPartNameFromRelative(
      $CorePropRelations[0]->getAttribute('Target'), '/' );
    my $CorePropXML = $Package->PartContents( $CorePropPartName );
    my $CorePropSchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/opc-coreProperties.xsd" );
    eval {
      my $CorePropDoc = XML::LibXML->new()->parse_string( $CorePropXML );
      $CorePropSchema->validate( $CorePropDoc );
    };
    if( $@ ) {
      return $CorePropPartName." is not a valid XML or is not valid against ".
        "opc-coreProperties.xsd:\n$@";
    }

    unless( $Package->PartContentType( $CorePropPartName ) eq CORE_PROPERTIES_CT ) {
      return "Wrong content type for $CorePropPartName"
    }
  }

  # В пакете должна быть как минимум одна часть, описывающая заголовок книги

  my @DescrRelationNodes = $XPC->findnodes(
    '/opcr:Relationships/opcr:Relationship[@Type="'.RELATION_TYPE_FB3_BOOK.'"]',
    $PackageRelsDoc );

  unless( @DescrRelationNodes ) {
    return "FB3 description not found";
  }

  for my $DescrRelationNode ( @DescrRelationNodes ) {
    
    # Каждую часть с описанием проверяем на валидность и соответствие схеме

    my $DescrPartName = OPC::FullPartNameFromRelative(
      $DescrRelationNode->getAttribute('Target'), '/' );
    my $DescrXML = $Package->PartContents( $DescrPartName );
    my $DescrSchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/fb3_descr.xsd" );
    my $DescrDoc;
    eval {
      $DescrDoc = XML::LibXML->new()->parse_string( $DescrXML );
      $DescrSchema->validate( $DescrDoc );
    };
    if( $@ ) {
      return $DescrPartName." is not a valid XML or is not valid against ".
        "fb3_descr.xsd:\n$@";
    }

    # Часть с описанием обязательно должна содержать в себе ссылку на тело книги

    $DescrPartName =~ /^(.*)\/([^\/]*)$/;
    my( $DescrDir, $DescrFileName ) = ( $1, $2 );
    my $DescrRelsPartName = "$DescrDir/_rels/$DescrFileName.rels";
    my $DescrRelsXML = $Package->PartContents( $DescrRelsPartName );
    unless( $DescrRelsXML ) {
      return "Can't find relationships for book description $DescrPartName ".
        "(no $DescrRelsPartName)";
    }
    my $DescrRelsDoc = XML::LibXML->new()->parse_string( $DescrRelsXML );
    my $BodyRelation = $XPC->findvalue(
      '/opcr:Relationships/opcr:Relationship[@Type="'.RELATION_TYPE_FB3_BODY.'"]/@Target',
      $DescrRelsDoc,
    ); 
    unless( $BodyRelation ) {
      return "Can't find body relationship for $DescrPartName";
    }
    my $BodyPartName = OPC::FullPartNameFromRelative( $BodyRelation,
      $DescrDir );

    # Найденную часть с телом книги также проверяем на валидность и соответствие схеме

    my $BodyXML = $Package->PartContents( $BodyPartName );
    my $BodySchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/fb3_body.xsd" );
    my $BodyDoc;
    eval {
      $BodyDoc = XML::LibXML->load_xml(string=>$BodyXML, huge => 1);
      $BodySchema->validate( $BodyDoc );
    };
    if( $@ ) {
      return $BodyPartName." is not a valid XML or is not valid against ".
        "fb3_body.xsd:\n$@";
    }
  }

  return ''; # успешный выход
}

sub IsValidPartName {
	my $PartName = shift;

	# "A part URI shall not have a forward slash as the last character. [M1.5]"
	return 0 if $PartName =~ /\/$/;

	# Проверяем отдельные сегменты имени
	for my $NameSegment ( split '/', $PartName ) {

		# "A segment shall not contain percent-encoded forward slash (“/”), or backward
		# slash (“\”) characters. [M1.7]"
		# "A segment shall not contain percent-encoded unreserved characters. [M1.8]"
		for my $Char (( '/', '\\', 'a'..'z', 0..9, '-', '.', '_', '~' )) {
			my $PercentEncodedChar = sprintf( '%%%x', ord( $Char ));
			return 0 if $NameSegment =~ /$PercentEncodedChar/i; 
		}

		# "A segment shall not end with a dot (“.”) character. [M1.9]"
		return 0 if $NameSegment =~ /\.$/;

		# "A segment shall include at least one non-dot character. [M1.10]"
		# (избыточное условие, удовлетворяющееся с помощью M1.9)
	}

	return 1;
}

sub _SourceByRelsPartName {
  my $RelsPartName = shift;

  my( $SourceDir, $SourceFileName ) = ( $RelsPartName =~ /
    ^ ( .* )  # папка файла источника
    _rels\/
    ([^\/]*)  # название файла источника без папки
    .rels /x );
  
  return ( $SourceDir, $SourceFileName );
}

1;
