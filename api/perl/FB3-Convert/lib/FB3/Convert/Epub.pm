package FB3::Convert::Epub;

use strict;
use base 'FB3::Convert';
use XML::LibXML;
use File::Basename;
use Clone qw(clone);
use utf8;

my %NS = (
  'container' => 'urn:oasis:names:tc:opendocument:xmlns:container',
  'root' => 'http://www.idpf.org/2007/opf',
  'xhtml' => 'http://www.w3.org/1999/xhtml',
  'dc' => 'http://purl.org/dc/elements/1.1/',
);

sub Reaper {
  my $self = shift;
  my $X = shift;

  my %Args = @_;
  my $Source = $Args{'source'} || die "Source path not defined";
  my $XC = XML::LibXML::XPathContext->new();

  $XC->registerNs('container', $NS{'container'});
  $XC->registerNs('root', $NS{'root'});
  $XC->registerNs('dc', $NS{'dc'});

  my $AllowElements = $X->{'allow_elements'};
### Обработчики нод для epub
  $AllowElements->{'img'} = {
    'allow_attributes' => ['src','href'],
    'processor' => \&ProcessImg,
  };
  $AllowElements->{'a'} = {
    'allow_attributes' => ['src','id','xlink:href'],
    'processor' => \&ProcessHref,
  };
  $AllowElements->{'b'} = {
    'allow_attributes' => [],
    processor => \&TransformTo,
    processor_params => ['strong']
  };
  $AllowElements->{'u'} = {
    'allow_attributes' => [],
    processor => \&TransformTo,
    processor_params => ['underline']
  };
  $AllowElements->{'div'} = {
    'exclude_if_inside' => ['p','ul','ol','h1','h2','h3','h4','h5','h6','li','pre','table'], #Если div содежрит block-level элементы, мы его чикаем 
    'allow_attributes' => [],
    processor => \&TransformTo,
    processor_params => ['p'],
    'allow_elements_inside' => $FB3::Convert::ElsMainList,
  };
  $AllowElements->{'h1'} = {
    'allow_attributes' => ['id'],
    processor => \&TransformH2Title,
    'allow_elements_inside' => {'p'=>undef},
  };
  $AllowElements->{'h2'} = $AllowElements->{'h1'};
  $AllowElements->{'h3'} = $AllowElements->{'h1'};
  $AllowElements->{'h4'} = $AllowElements->{'h1'};
  $AllowElements->{'h5'} = $AllowElements->{'h1'};
  $AllowElements->{'h6'} = $AllowElements->{'h1'};

##### где хранится содержимое книги
  my $ContainerFile = $Source."/META-INF/container.xml";
  die $self." ".$ContainerFile." not found!" unless -f $ContainerFile;

  $X->Msg("Parse container ".$ContainerFile."\n");
  my $CtDoc = XML::LibXML->new()->parse_file($ContainerFile) || die "Can't parse file ".$ContainerFile;
  my $RootFile = $XC->findnodes('/container:container/container:rootfiles/container:rootfile',$CtDoc)->[0]->getAttribute('full-path');
  die "Can't find full-path attribute in Container [".$NS{'container'}." space]" unless $RootFile;

#### root-файл с описанием контента
  $RootFile = $Source."/".$RootFile;
  die "Can't find root (full-path attribute) file ".$RootFile unless -f $RootFile;

  #Директория, относительно которой лежит контент. Нам с ней еще работать
  $X->{'ContentDir'} = $RootFile;
  $X->{'ContentDir'} =~ s/\/?[^\/]+$//;

  $X->Msg("Parse rootfile ".$RootFile."\n");
  
  my $RootDoc = XML::LibXML->load_xml( location => $RootFile ) || die "Can't parse file ".$RootFile;
  $RootDoc->setEncoding('utf-8');

  # список файлов с контентом
  my @Manifest;
  for my $MItem ($XC->findnodes('/root:package/root:manifest/root:item',$RootDoc)) {
    push @Manifest, {
      'id' => $MItem->getAttribute('id'),
      'href' => $MItem->getAttribute('href'),
      'type' => $MItem->getAttribute('media-type'),
    };
  }
  my @Spine;
  for my $MItem ($XC->findnodes('/root:package/root:spine/root:itemref',$RootDoc)) {
    my $IdRef = $MItem->getAttribute('idref');
    push @Spine, $IdRef;
  }

  $X->Msg("Assemble content\n");
  my $AC = AssembleContent($X, 'manifest' => \@Manifest, 'spine' => \@Spine);

  # Отдаем контент на обработку

  #Заполняем внутренний формат

  #МЕТА
  my $Structure = $X->{'STRUCTURE'};
  my $Description = $Structure->{'DESCRIPTION'};

  my $GlobalID;  
  unless (defined $Description->{'DOCUMENT-INFO'}->{'ID'}) { 
    $Description->{'DOCUMENT-INFO'}->{'ID'} = $GlobalID = $X->UUID();
  }

  unless (defined $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'}) {
    my $Lang = $XC->findnodes('/root:package/root:metadata/dc:language',$RootDoc)->[0];
    $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'} =  $self->html_trim($Lang->to_literal) if $Lang;
  }

  unless (defined $Description->{'TITLE-INFO'}->{'BOOK-TITLE'}) {
    my $Title = $XC->findnodes('/root:package/root:metadata/dc:title',$RootDoc)->[0];
    $Description->{'TITLE-INFO'}->{'BOOK-TITLE'} = $self->EncodeUtf8($self->html_trim($Title->to_literal)) if $Title;
  }

  unless (defined $Description->{'TITLE-INFO'}->{'ANNOTATION'}) {
    my $Annotation = $XC->findnodes('/root:package/root:metadata/dc:description',$RootDoc)->[0];
    $Description->{'TITLE-INFO'}->{'ANNOTATION'} = $self->EncodeUtf8($self->EraseTags($self->html_trim($Annotation->to_literal))) if $Annotation;
  }

  unless (defined $Description->{'TITLE-INFO'}->{'PUBLISHER'}) {
    my $Publisher = $XC->findnodes('/root:package/root:metadata/dc:publisher',$RootDoc)->[0];
    $Description->{'TITLE-INFO'}->{'PUBLISHER'} = $self->EncodeUtf8($self->html_trim($Publisher->to_literal)) if $Publisher;
  }
  
  unless (defined $Description->{'TITLE-INFO'}->{'GENRES'}) { 
    my @Genres;
    for my $Genre ($XC->findnodes('/root:package/root:metadata/dc:subject',$RootDoc)) {
      next unless $Genre->to_literal;
      push @Genres, $self->html_trim($Genre->to_literal),
    }
    push @Genres, 'Unknown' unless @Genres;
    
    $Description->{'TITLE-INFO'}->{'GENRES'} = \@Genres;
  }

  unless (defined $Description->{'DOCUMENT-INFO'}->{'DATE'}) {
    my($day, $month, $year, $hour, $min, $sec)=(localtime)[3,4,5,2,1,0];
    $Description->{'DOCUMENT-INFO'}->{'DATE'} = {
      'attributes' => {
        'value' => ($year+1900).'-'.sprintf("%02d",($month+1)).'-'.sprintf("%02d",$day),
      }
    };
    $Description->{'DOCUMENT-INFO'}->{'TIME'} = {
      'attributes' => {
        'value' => sprintf("%02d",$hour).':'.sprintf("%02d",$min).':'.sprintf("%02d",$sec),
      }
    };
  }

  unless (defined $Description->{'TITLE-INFO'}->{'AUTHORS'}) {
    my @Authors;
    for my $Author ($XC->findnodes('/root:package/root:metadata/dc:creator',$RootDoc)) {
      my $Author = $self->BuildAuthorName($self->EncodeUtf8($self->html_trim($Author->to_literal)));
      push @Authors, $Author;
    }
    push @Authors, $self->BuildAuthorName('Unknown');
    $Description->{'TITLE-INFO'}->{'AUTHORS'} = \@Authors;
  }

  #print Data::Dumper::Dumper($AC);
  
  #КОНТЕНТ

  my @Pages;
  foreach (@$AC) {
    $X->Msg("Processing in structure: ".$_->{'file'}."\n",'i');
    push @Pages, $X->Content2Tree($_);
  }

  # [#01]
  my @PagesComplete;

  #Клеим смежные title
  #Отрезаем ненужное
  foreach my $Page (@Pages) {

    $Page->{'content'} = CleanNodeEmptyId($X,$Page->{'content'});

    #^<p/> и emptyline режем в начале
    foreach my $Item (@{$Page->{'content'}}) {

      if (
          ref $Item eq 'HASH'
          && exists $Item->{'p'}
          && ( $X->IsEmptyLineValue($Item->{'p'}->{'value'}) )
        ) {
        $Item = undef;
      } else {
        last;
      }
    }

    #^<p/> и emptyline режем в конце
    foreach my $Item (reverse @{$Page->{'content'}}) {
      if (
          ref $Item eq 'HASH'
          && exists $Item->{'p'}
          && ( $X->IsEmptyLineValue($Item->{'p'}->{'value'}) )
        ) {
        $Item = undef;
      } else {
        last;
      }
    }
    
    my $c=-1;
    my $EmptyLineDetect=undef;
    foreach my $Item (@{$Page->{'content'}}) {
      $c++;
      next unless defined $Item;
      if (ref $Item eq '' && $X->trim($Item) eq '') {
        $Item=undef;
        next;
      }
      
      #клеим смежные emptyline
      if (ref $Item eq 'HASH'
          && exists $Item->{'p'}
          && $X->IsEmptyLineValue($Item->{'p'}->{'value'})
        ) {
       
        if (defined $EmptyLineDetect) {
          push @{$Page->{'content'}->[$EmptyLineDetect]->{p}->{'value'}}, $Item->{'p'}->{'value'};
          $Item = undef;
          next;
        }
        $EmptyLineDetect = $c;
      } else {
        $EmptyLineDetect = undef;
      }
    
      #<title/> иногда попадаются - режем
      if (
          ref $Item eq 'HASH'
          && exists $Item->{'title'}
        ) {
          $Item->{'title'}->{'value'} = CleanTitle($X,$Item->{'title'}->{'value'});
          $Item = undef unless @{$Item->{'title'}->{'value'}};
      }
      
    }

    for (my $c = scalar @{$Page->{'content'}}; $c>=0; $c--) {
        my $Item = $Page->{'content'}->[$c];
        my $LastTitleOK = -1;

        next if (ref $Item ne 'HASH' || !exists $Item->{'title'});

        for (my $i=$c-1;$i>=0;$i--) { #бежим назад и ищем, нет ли перед нами title?

          my $Last = $Page->{'content'}->[$i];

          next if !ref($Last) && $X->trim($Last) eq ''; #если перед нами перенос строки, игнорим, ищем title дальше

          if (ref $Last eq 'HASH' && exists $Last->{'title'}) { #перед нами title, будем клеить текущий title с ним
            $LastTitleOK = $i;
            last;
          } else {
            last; #наткнулись на НЕ-title, хватит перебирать
          }
          
        }

        if ($LastTitleOK > -1) {
          push @{$Page->{'content'}->[$LastTitleOK]->{'title'}->{'value'}}, clone(\@{$Item->{'title'}->{'value'}}); #переносим title в предыдущий
          delete $Page->{'content'}->[$c];
          delete $Page->{'content'}->[$c-1] #перенос строки тоже грохнем
            if (
              !ref $Page->{'content'}->[$c-1]
              && $X->trim($Page->{'content'}->[$c-1]) eq ''
            );
        }

    }

    #РИсуем section's
     my @P;
     my $Sec = { #заготовка section
      'section' => {
        'value' => [],
        'attributes' => {
          'id' => $Page->{'ID_SUB'},
        }
      }
     };

     my $c=0;
     my $TitleOK = 0;
     push @{$Page->{'content'}},''; #пустышка-закрывашка (так легче обработать массив)
     foreach my $Item (@{$Page->{'content'}}) {

      $c++;
      if (ref $Item eq 'HASH') {
        my ($Key) = each %$Item;
        if ($Key =~ /^title$/) {
          $TitleOK = 1;
        } else {
          $TitleOK = 0;
        }
      } else {
        $TitleOK = 0;
      }

      if ($TitleOK) { #встретили title
        push @P, clone($Sec) if @{$Sec->{'section'}->{'value'}};
        $Sec->{'section'}->{'value'} = []; #надо закрыть section
        push @{$Sec->{'section'}->{'value'}}, $Item; #и продолжить пушить в новый
        next;
      }

      push @{$Sec->{'section'}->{'value'}}, $Item if $Item;

      if ( #страница закрывается, пушим section что там в нем осталось
        $c >= scalar @{$Page->{'content'}}
      ) {
        push @P, clone($Sec);
        $Sec->{'section'}->{'value'} = [];
      }

    }

    #одиночки title нам в section не нужны - не валидно
    #таких разжалуем в subtitle
    foreach my $Sec (@P) {
      my $Last = pop @{$Sec->{'section'}->{'value'}};
      push @{$Sec->{'section'}->{'value'}}, $Last unless (ref $Last eq '' && $X->trim($Last) eq '') ;

      if (
       scalar @{$Sec->{'section'}->{'value'}} == 1
        && ref $Sec->{'section'}->{'value'}->[0] eq 'HASH'
        && exists $Sec->{'section'}->{'value'}->[0]->{'title'}
      ) {

        $Sec->{'section'}->{'value'} = 
          [
           {
            'subtitle' => {
             'value' => $Sec->{'section'}->{'value'}->[0]->{'title'}->{'value'}->[0]->{'p'}->{'value'}
            }
           }
          ];

      }

    }

    my $Content;
    if (scalar @P > 1) {
      $Content = \@P;
    } else {
      $Content = $P[0]->{'section'}->{'value'};  #если section один, то берем только его внутренности, контейнер section лишний 
    }

    push @PagesComplete, {ID=>$Page->{'ID'},'content'=>$Content};
  }
  @Pages = ();

  my @Body;
  foreach my $PC (@PagesComplete) {
    push @Body,  {
      'section' => {
        attributes=>{
          'id' => $PC->{'ID'}
        },
        'value' => $PC->{'content'},
      }
    };
  }

  $Structure->{'PAGES'} = {
    value => \@Body
  };

}

sub AssembleContent {
  my $X = shift;
  my %Args = @_;
  my $Manifest = $Args{'manifest'} || [];
  my $Spine = $Args{'spine'} || [];

  my @Pages;
  my $XC = XML::LibXML::XPathContext->new();
  $XC->registerNs('xhtml', $NS{'xhtml'});

  $X->Error('Spin list is empty or not defined!') unless scalar @$Spine;

  my %ReverseManifest; #так проще грепать
  my $Ind=0;
  foreach my $Item (@$Manifest) {
    $Ind++;
    $ReverseManifest{$Item->{'id'}} = $Item;

    # !! Стили пока не трогаем !!
    #if ($Item->{'type'} =~ /^text\/css$/) { # В манифесте css 
    #  push @{$X->{'STRUCTURE'}->{'CSS_LIST'}}, {
    #    'src_path' => $Item->{'href'},
    #    'new_path' => undef,
    #    'id' => $Item->{'id'},
    #  };
    #}

  }

  #бежим по списку, составляем скелет контекстной части
  for my $ItemID (@$Spine) {

    if (!exists $ReverseManifest{$ItemID}) {
      $X->Msg("id ".$ItemID." not exists in Manifest list\n",'i');
      next;
    }

    my $Item = $ReverseManifest{$ItemID};
    if ($Item->{'type'} =~ /^application\/xhtml/) { # Видимо, текст

      my $ContentFile = $X->{'ContentDir'}.'/'.$Item->{'href'};

      $X->Msg("Parse content file ".$ContentFile."\n");

      my $ContentDoc = XML::LibXML->load_xml(
        location => $ContentFile,
        expand_entities => 0, # не считать & за entity
        no_network => 1, # не будем тянуть внешние вложения
        recover => 2, # не падать при кривой структуре. например, не закрыт тег. entity и пр | => 1 - вопить, 2 - совсем молчать
        load_ext_dtd => 0 # полный молчок про dtd
      );
      $ContentDoc->setEncoding('utf-8');
      
      my $Body = $XC->findnodes('/xhtml:html/xhtml:body',$ContentDoc)->[0];
      
      $X->Error("Can't find /html/body node in file $ContentFile. This is true XML?") unless $Body;

      #перерисуем все ns-подобные атрибуты. мешают при дальнейшем парсинге
      foreach my $NodeAttr ( $XC->findnodes('//*[@*]', $Body) ) {
        my @Attrs = $NodeAttr->findnodes( "./@*");
        foreach my $Attr (@Attrs) {
          if ($Attr->nodeName =~ /^.+:(.+)/) { #если атриббут похож на ns

            my $AttrName = $1;
            my $AttrValue =   $NodeAttr->getAttribute($Attr->nodeName);

            $NodeAttr->setAttribute($AttrName => $AttrValue) unless $NodeAttr->getAttribute($AttrName); #переименуем ns-Образный в обычный, если такового нет
            $NodeAttr->removeAttribute( $Attr->nodeName ); #удалим ns-образный
          }
        }
      }

      #при сборе fb3 тэг title разрешен, но в body ему появляться нельзя.
      #резанем костылем по шее
      for my $node ($XC->findnodes('//xhtml:title',$Body)) {
        $node->parentNode()->removeChild($node);
      }

      my $Content = $X->InNode($Body);
      $Content =~ s/^\s*//;
      $Content =~ s/\s*$//;
      push @Pages, {
        content=>$Content,
        file=>$Item->{'href'}
      };
  
    } else {
      $X->Msg("ID ".$Item->{'id'}.": I not understood what is it '".$Item->{'type'}."[".$Item->{'href'}."]'\n",'w');
    }

  }

  return (
    pages => \@Pages,            
  );

}

sub CleanTitle {
  my $X = shift;
  my $Node = shift;

  return $Node unless ref $Node eq 'ARRAY';

  foreach my $Item (@$Node) {
    $Item = undef if ref $Item eq 'HASH' && exists $Item->{'p'} && !scalar @{$Item->{'p'}->{'value'}};  
  }

  my @Ret;
  foreach (@$Node) {
    push @Ret, $_ if defined $_;
  }
  
  return \@Ret;
}

sub CleanNodeEmptyId {
  my $X = shift;
  my $Node = shift;

  return $Node unless ref $Node eq 'ARRAY';

  my $Ret = [];

  foreach my $Item (@$Node) {
    push @$Ret, $Item;
    next unless ref $Item eq 'HASH';
    foreach my $El (keys %$Item) {
      $Item->{$El}->{'value'} = CleanNodeEmptyId($X,$Item->{$El}->{'value'});
      if (exists $Item->{$El}->{'attributes'}->{'id'}) {
        my $Id = $Item->{$El}->{'attributes'}->{'id'};
        unless (exists $X->{'href_list'}->{"#".$Id}) { #элементы с несуществующими id
          $X->Msg("Find non exists ID and delete '$Id' in node '$El' [".$X->{'id_list'}->{$Id}."]\n","w");
          delete $Item->{$El}->{'attributes'}->{'id'}; #удалим id
          next unless $El =~ /^(a|span)$/;
          my $Link = $X->trim($Item->{$El}->{'attributes'}->{'xlink:href'});
          if ($El eq 'a' && $Link ne '') { #<a> c линками оставим
            $X->Msg("Find link [$Link]. Skip\n");
            next;
          }
          pop @$Ret;
          push @$Ret, @{$Item->{$El}->{'value'}} if scalar @{$Item->{$El}->{'value'}}; #переносим на место ноды ее внутренности
          $X->Msg("Delete node '$El'\n");
        }
      }
    }
  }

  return $Ret;
}

#Процессоры обработки нод

# Копируем картинки, перерисовывает атрибуты картинок на новые
sub ProcessImg {
  my $X = shift;
  my %Args = @_;
  my $Node = $Args{'node'};
  my $RelPath = $Args{'relpath'};

  my $ImgList = $X->{'STRUCTURE'}->{'IMG_LIST'};
  my $Src = $Node->getAttribute('src');

  #честный абсолютный путь к картинке
  my $ImgSrcFile = $X->RealPath(FB3::Convert::dirname($X->RealPath( $RelPath ? $X->{'ContentDir'}.'/'.$RelPath : $X->{'ContentDir'})).'/'.$Src);

  $X->Msg("Find img, try transform: ".$Src."\n","w");

  my $ImgDestPath = $X->{'DestinationDir'}."/fb3/img";

  $Src =~ /.([^\/\.]+)$/;
  my $ImgType = $1;

  my $ImgID = 'img_'.$X->UUID($ImgSrcFile);
  my $NewFileName = $ImgID.'.'.$ImgType;
  my $ImgDestFile = $ImgDestPath.'/'.$NewFileName;

  push @$ImgList, {
    'new_path' => "img/".$NewFileName, #заменим на новое имя
    'id' => $ImgID,
  } unless grep {$_->{id} eq $ImgID} @$ImgList;

  #Копируем исходник на новое место с новым уникальным именем
  unless (-f $ImgDestFile) {
    $X->Msg("copy $ImgSrcFile -> $ImgDestFile\n");
    FB3::Convert::copy($ImgSrcFile, $ImgDestFile) or $X->Error($!." [copy $ImgSrcFile -> $ImgDestFile]");        
  }

  $Node->setAttribute('src' => $ImgID);

  return $Node;
}

# Перерисовываем href
sub ProcessHref {
  my $X = shift;
  my %Args = @_;
  my $Node = $Args{'node'};
  my $RelPath = $Args{'relpath'};

  my $Href = $Node->getAttribute('href') || "";

  my ($Link, $Anchor) = split /\#/, $Href, 2;

  my $NewHref =
  $Href ?
        $Href =~ /^[a-zA-Z]+\:/
          ? $Href
          : '#'.($Anchor ? 'link_' : '').$X->Path2ID( ($Link
                                                       ?$Href: #внешний section
                                                       basename($RelPath)."#".$Anchor #текущий section
                                                       ), $RelPath , 'process_href')
        : '';
        
        
  $X->{'href_list'}->{$NewHref} = $Href if $X->trim($NewHref) ne '';     
  $Node->setAttribute('xlink:href' => $NewHref);

  return $Node;  
}

sub TransformTo {
  my $X = shift;
  my %Args = @_;
  my $Node = $Args{'node'};
  my $To = $Args{'params'}->[0];

  $Node->setNodeName($To);
  return $Node;
}

sub TransformH2Title {
  my $X = shift;
  my %Args = @_;
  my $Node = $Args{'node'};

  $Node->setNodeName('title');

  foreach my $Child ($Node->getChildnodes) {
    next if $Child->nodeName =~ /^p$/i;
    my $NewNode = XML::LibXML::Element->new("p");
    $NewNode->addChild($Child->cloneNode(1));
    $Child->replaceNode($NewNode);
  }
  
  return $Node;
}

1;
