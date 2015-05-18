package XPortal::FB3;

use strict;
use Archive::Zip qw/ :ERROR_CODES :CONSTANTS /;
use XML::LibXML;
use URI::Escape;

use Data::Dumper;

our $XSD_DIR = "$XPortal::Settings::Path/xsd/fb3";

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

# Возвращает пустую строку в случае успеха и текст ошибки в противном случае
sub Validate {
  my $FileName = shift;

  # Проверка, что файл - валидный ZIP архив

  my $Zip = Archive::Zip->new();
  my $ReadStatus = $Zip->read( $FileName );
  unless( $ReadStatus == AZ_OK ) {
    return $ReadStatus == AZ_FORMAT_ERROR ? 'Given file is not a valid ZIP archive' :
                                            'Failed to open ZIP archive';
  }

  # Проверка правильности метода сжатия (deflated или stored)
  
  for my $Member ( $Zip->members ) {
    unless( grep $Member->compressionMethod == $_, COMPRESSION_STORED,
        COMPRESSION_DEFLATED ) {

      return 'Item "'. $Member->fileName .'" uses unsupported compression method. '.
        'Need "stored" of "deflated"';
    }
  }

  my %Namespaces = (
    opcct => 'http://schemas.openxmlformats.org/package/2006/content-types',
    opcr => 'http://schemas.openxmlformats.org/package/2006/relationships',
  );
  my $XPC = XML::LibXML::XPathContext->new();
  $XPC->registerNs( $_ => $Namespaces{$_} ) for keys %Namespaces;

  # Находим Content Types Stream, проверяем валидность
  # и возвращаем хэш [имя файла в архиве] => [Content type]

  my %CtByNormalizedName = do {
    my $CtMember = $Zip->memberNamed( '[Content_Types].xml' );
    unless( $CtMember ) {
      return "[Content_Types].xml not found";
    }
    my $CtSchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/opc-contentTypes.xsd" );
    my $CtDoc;
    eval {
      $CtDoc = XML::LibXML->new()->parse_string( $CtMember->contents() );
      $CtSchema->validate( $CtDoc );
    };
    if( $@ ) {
      return "[Content_Types].xml is not a valid XML or is invalid against XSD schema:\n$@";
    }

    my %CtByExtension =
      map{ NormalizeName($_->getAttribute('Extension')) => $_->getAttribute('ContentType') }
      $XPC->findnodes( '/opcct:Types/opcct:Default', $CtDoc );

    my %CtByPartName =
      map{ NormalizeName($_->getAttribute('PartName')) => $_->getAttribute('ContentType') }
      $XPC->findnodes( '/opcct:Types/opcct:Override', $CtDoc );

    map {
        my $NormalizedName = PartNameFromZipItem($_);

        $NormalizedName =~ /\.([^.]+)$/;
        my $Extension = $1;
        if( defined $CtByPartName{ $NormalizedName } ) {
          ( $NormalizedName => $CtByPartName{ $NormalizedName } );
        } else {
          ( $NormalizedName => $CtByExtension{ $Extension } );
        }
      } $Zip->memberNames;
  };

  # Далее удобно работать не с ZIP именами, а с именами в формате частей OPC
  # (однако не все ZIP файлы окажутся частями OPC)

  my( %MemberByNormalizedName, @NormalizedMemberNames );
  for my $Member ( $Zip->members ) {
    my $NormalizedName = PartNameFromZipItem( $Member->fileName );
    push @NormalizedMemberNames, $NormalizedName;
    $MemberByNormalizedName{ $NormalizedName } = $Member;
  }

  # Находим все части, описывающие связи (Relationships).

  my @RelsPartNames;
  for my $NormalizedName ( @NormalizedMemberNames ) {
    my( $SourceDir, $SourceFileName ) = SourceByRelsPartName( $NormalizedName );
    if( defined $SourceDir && defined $SourceFileName ) {
      my $SourcePartName = $SourceDir.$SourceFileName;

      if( $SourcePartName eq "/"  # источник - сам архив
          || grep $SourcePartName eq $_, @NormalizedMemberNames  # источник есть в архиве
          ) {

        push @RelsPartNames, $NormalizedName
          unless grep $NormalizedName eq $_, @RelsPartNames;
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
    my $RelsMember = $MemberByNormalizedName{ $RelsPartName };
    eval {
      $RelsDoc = XML::LibXML->new()->parse_string( $RelsMember->contents );
      $RelsSchema->validate( $RelsDoc );
    };
    if( $@ ) {
      return $RelsPartName." is not a valid XML or is not valid against ".
        "opc-relationships.xsd:\n$@";
    }

    # У Relationships частей должен быть соответствующий Content Type

    unless( $CtByNormalizedName{ $RelsPartName } eq RELATIONSHIPS_CT ) {
      return "Wrong content type for $RelsPartName (OPC M1.30 violation)"
    }

    # Проверки отдельных связей

    my( $SourceDir ) = SourceByRelsPartName( $RelsPartName );
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

        my $RelatedPartName = FullNameFromRelative( $RelNode->getAttribute('Target'),
          $SourceDir );

        unless( grep $RelatedPartName eq $_, @NormalizedMemberNames ) {
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
    
    # Не должно быть частей с эквивалентными названиями [M1.12]

    my @FoundMemberNames = grep $PartName eq PartNameFromZipItem($_), $Zip->memberNames;
    if( @FoundMemberNames > 1 ) {
      return "There several zip items with part name $PartName: ".
        ( join ', ', @FoundMemberNames )." (OPC M1.12 violation)";
    }

    # У всех частей должен быть задан Content type [M1.2], хотя он может быть
    # пустым [M1.14]

    unless( defined $CtByNormalizedName{ $PartName } ) {
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
    my $CorePropPartName = FullNameFromRelative(
      $CorePropRelations[0]->getAttribute('Target'), '/' );
    my $CorePropMember = $MemberByNormalizedName{ $CorePropPartName };
    my $CorePropSchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/opc-coreProperties.xsd" );
    eval {
      my $CorePropDoc = XML::LibXML->new()->parse_string( $CorePropMember->contents );
      $CorePropSchema->validate( $CorePropDoc );
    };
    if( $@ ) {
      return $CorePropPartName." is not a valid XML or is not valid against ".
        "opc-coreProperties.xsd:\n$@";
    }
  
    unless( $CtByNormalizedName{ $CorePropPartName } eq CORE_PROPERTIES_CT ) {
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
  
    my $DescrPartName = FullNameFromRelative( $DescrRelationNode->getAttribute('Target'),
      '/' );
    my $DescrMember = $MemberByNormalizedName{ $DescrPartName };
    my $DescrSchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/fb3_descr.xsd" );
    my $DescrDoc;
    eval {
      $DescrDoc = XML::LibXML->new()->parse_string( $DescrMember->contents );
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
    my $DescrRelsMember = $MemberByNormalizedName{ $DescrRelsPartName };
    unless( $DescrRelsMember ) {
      return "Can't find relationships for book description $DescrPartName ".
        "(no $DescrRelsPartName)";
    }
    my $DescrRelsDoc = XML::LibXML->new()->parse_string( $DescrRelsMember->contents );
    my $BodyRelation = $XPC->findvalue(
      '/opcr:Relationships/opcr:Relationship[@Type="'.RELATION_TYPE_FB3_BODY.'"]/@Target',
      $DescrRelsDoc,
    ); 
    unless( $BodyRelation ) {
      return "Can't find body relationship for $DescrPartName";
    }
    my $BodyPartName = FullNameFromRelative( $BodyRelation, $DescrDir );
  
    # Найденную часть с телом книги также проверяем на валидность и соответствие схеме
  
    my $BodyMember = $MemberByNormalizedName{ $BodyPartName };
    my $BodySchema = XML::LibXML::Schema->new( location =>
      "$XSD_DIR/fb3_body.xsd" );
    my $BodyDoc;
    eval {
      $BodyDoc = XML::LibXML->new()->parse_string( $BodyMember->contents );
      $BodySchema->validate( $BodyDoc );
    };
    if( $@ ) {
      return $BodyPartName." is not a valid XML or is not valid against ".
        "fb3_body.xsd:\n$@";
    }
  }

  # TODO куча требований к именованию частей:
  # A part IRI shall not be empty. [M1.1]
  # A part IRI shall not have empty isegments. [M1.3]
  # A part IRI shall start with a forward slash (“/”) character. [M1.4]
  # A part IRI shall not have a forward slash as the last character. [M1.5]
  # An isegment shall not hold any characters other than ipchar characters. [M1.6]
  # An isegment shall not contain percent-encoded forward slash (“/”), or backward
    # slash (“\”) characters. [M1.7]
  # An isegment shall not contain percent-encoded iunreserved characters. [M1.8]
  # An isegment shall not end with a dot (“.”) character. [M1.9]
  # An isegment shall include at least one non-dot character. [M1.10]
  # A package implementer shall neither create nor recognize a part with a part name
    # derived from another part name by appending segments to it. [M1.11]

  # TODO General XML
  # [M1.17] - UTF-8 or UTF-16. Если есть упоминания encoding в самом XML - это тоже
    # UTF-8 или UTF-16.
  # [M1.18] shall treat the presence of DTD declarations as an error.
  # [M1.19] remove Markup Compatibility elements and attributes, ignorable namespace
    # declarations, and ignored elements and attributes before applying subsequent
    # validation rules.
  # [M1.20] valid against corresponding schemes
  # [M1.21] no elements or attributes drawn from “xml” or “xsi” namespaces

  return ''; # успешный выход
}

sub NormalizeName {
  my $PartName = shift;

  use bytes; # чтобы lc действовал только на ASCII
  $PartName = lc( $PartName );
  $PartName = uri_unescape( $PartName );

  return $PartName;
}

sub PartNameFromZipItem {
  my $ZipItemName = shift;

  return NormalizeName( "/$ZipItemName" );
}

sub SourceByRelsPartName {
  my $RelsPartName = shift;

  my( $SourceDir, $SourceFileName ) = ( $RelsPartName =~ /
    ^ ( .* )  # папка файла источника
    _rels\/
    ([^\/]*)  # название файла источника без папки
    .rels /x );
  
  return ( $SourceDir, $SourceFileName );
}

sub FullNameFromRelative {
  my $Name = shift;
  my $Dir = shift;
  $Dir =~ s:/$::; # убираем последний слэш

  my $FullName = ( $Name =~ m:^/: ) ? $Name :       # в $Name - полный путь
                                      "$Dir/$Name"; # в $Name - относительная ссылка

  # обрабатываем все . и .. в имени
  my @CleanedParts;
  my @OriginalParts = split m:/:, $FullName;
  for my $Part ( @OriginalParts ) {
    if( $Part eq '.' ) {
      # просто пропускаем
    } elsif( $Part eq '..' ) {
      pop @CleanedParts;
    } else {
      push @CleanedParts, $Part;
    }
  }

  return join '/', @CleanedParts;
}

1;
