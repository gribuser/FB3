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
  my $RootDoc = XML::LibXML->new()->parse_file($RootFile) || die "Can't parse file ".$RootFile;
  #  my $RootFile = $XC->findnodes('/root:package/root:rootfiles/container:rootfile',$CtDoc)->[0]->getAttribute('full-path');

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
   ## next if grep{$_ eq $IdRef} ("cover","title","annotation"); #очень не уверен, что это зарезервированные idref. Но в epub-мете нигде о них больше не сказано
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
    $Description->{'TITLE-INFO'}->{'BOOK-TITLE'} = $self->html_trim($Title->to_literal) if $Title;
  }

  unless (defined $Description->{'TITLE-INFO'}->{'ANNOTATION'}) {
    my $Annotation = $XC->findnodes('/root:package/root:metadata/dc:description',$RootDoc)->[0];
    $Description->{'TITLE-INFO'}->{'ANNOTATION'} = $self->EraseTags($self->html_trim($Annotation->to_literal)) if $Annotation;
  }

  unless (defined $Description->{'TITLE-INFO'}->{'PUBLISHER'}) {
    my $Publisher = $XC->findnodes('/root:package/root:metadata/dc:publisher',$RootDoc)->[0];
    $Description->{'TITLE-INFO'}->{'PUBLISHER'} = $self->html_trim($Publisher->to_literal) if $Publisher;
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
      my $Author = $self->BuildAuthorName($self->html_trim($Author->to_literal));
      push @Authors, $Author;
    }
    $Description->{'TITLE-INFO'}->{'AUTHORS'} = \@Authors;
  }

  #КОНТЕНТ

=pod
  my $AC= [
    
          {
            'file' => 'c02.xhtml',
            'content' => "
            
            <p>TEXT FROM 2________</p>  
<h1>UNDERSTANDING CONFIDENCE</h1>
<h1>UNDERSTANDING CONFIDENCE2</h1>
<p>ddddd</p>
<h1>UNDERSTANDING CONFIDENCE3</h1>
<p>END</p>
"},
 {
           'file' => 'ftitlepage.xhtml',
            'content' => '
<header>
 <h1 class="bookTitle"><span class="center">CONFIDENCE <des>DESSS</des> POCKETBOOK</span></h1>
</header>
<section>
  <h2 class="bookSubTitle"><span class="center">LITTLE EXERCISES FOR A SELF-ASSURED LIFE</span></h2>
  <p><b>Gill Hasson</b></p>
</section>
'
          },

          
];
  my $AC= [ 
          {
            'file' => 'fpart1.xhtml',
            'content' => '
            <p>fdfd</p>
<h1>ddddd</h1>
<h1/>
            <p>fdfd</p>
<h1>FOUNDATION STONES OF CONFIDENCE</h1>
'
          }];


my $AC = [ 
{
  'file' => 'xhtml/chapter12.xhtml',
  'content' => "
<div>HELLO DIV</div>
<div class=\"body1\">
<H2>HELLO</H2>
</div>
<H3>HELLO2</H3>
<div class=\"body\">
<p class=\"CN\" id=\"ch12\"><span id=\"pg_197\" title=\"197\" type=\"pagebreak\"/><a href=\"contents.xhtml#c_ch12\"><span class=\"ePub-B\">TWELVE</span></a></p>
<p class=\"CT\"><a href=\"contents.xhtml#c_ch12\"><span class=\"ePub-BI\">The Lessons of Jonas</span></a></p>
</div>
"}];

=cut

#print Data::Dumper::Dumper($AC);
#exit;

  my @Pages;
  foreach (@$AC) {
    $X->Msg("Processing in structure: ".$_->{'file'}."\n",'i');
    push @Pages, $X->Content2Tree($_);
  }

  # [#01]
  my @PagesComplete;

  #Клеим смежные title
  foreach my $Page (@Pages) {

    #<title/> иногда попадаются - режем
    foreach my $Item (@{$Page->{'content'}}) {
      if (
          ref $Item eq 'HASH'
          && exists $Item->{'title'}
          && !scalar @{$Item->{'title'}->{'value'}}
        ) {
        $Item = undef;
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
            #print "FIND TITLE".Data::Dumper::Dumper($Last->{'title'}->{'value'});
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
       # push @P, clone($Sec);
       # $Sec->{'section'}->{'value'} = [];
        next;

      }

      push @{$Sec->{'section'}->{'value'}}, $Item;

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

      delete $Sec->{'section'}->{'value'}->[@{$Sec->{'section'}->{'value'}} - 1]
        if !ref $Sec->{'section'}->{'value'}->[scalar @{$Sec->{'section'}->{'value'}} - 1]
        && $Sec->{'section'}->{'value'}->[scalar @{$Sec->{'section'}->{'value'}} - 1] eq '';

      if (
       scalar @{$Sec->{'section'}->{'value'}} == 1
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

    push @PagesComplete, {ID=>$Page->{'ID'},'content'=>\@P};
  }
  @Pages = ();

#print Data::Dumper::Dumper(\@PagesComplete);
#exit;
  
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

  my $XMLDoc = XML::LibXML->new(
    expand_entities => 0, # не считать & за entity
    no_network => 1, # не будем тянуть внешние вложения
    recover => 2, # не падать при кривой структуре. например, не закрыт тег. entity и пр | => 1 - вопить, 2 - совсем молчать
    load_ext_dtd => 0 # полный молчок про dtd
  );
  $XMLDoc->expand_entities(0); #или так?

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

#    if ($Item->{'id'} =~ /^cover$/) { # ты точно cover?!
#      my $CoverFile = $SelfData{'ContentDir'}.'/'.$Item->{'href'};
#      my $CoverDoc = $XMLDoc->parse_file($CoverFile) || die "Can't parse file ".$CoverFile;
#      my $Cover = $XC->findnodes('//xhtml:img',$CoverDoc)->[0];  #или может все-таки xhtml:img[@class="coverpage"] ? не слишком узко?
#        if ($Cover) {
#          my $CoverSrcPath = $Cover->getAttribute('src');

#          my $CoverId = "cover_".$Item->{'id'};
#          my $H = {
#            'src_path' => $Cover->{'src'},
#            'new_path' => undef,
#            'id' => $CoverId,
#          };
#          my $Cover = $X->ProcessImg(src=>$Cover->{'src'}); #грязный хак
#          $X->{'STRUCTURE'}->{'DESCRIPTION'}->{'TITLE-INFO'}->{'COVER'} = $Cover->{'new_path'};
#        }
#    }

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

      my $ContentDoc = $XMLDoc->parse_file($ContentFile) || die "Can't parse file ".$ContentFile;

      my $Body = $XC->findnodes('/xhtml:html/xhtml:body',$ContentDoc)->[0];

      #перерисуем все ns-подобные атрибуты. мешают при дальнейшем парсинге
      foreach my $NodeAttr ( $XC->findnodes('//*[@*]', $Body) ) {
        my @Attrs = $NodeAttr->findnodes( "./@*");
        foreach my $Attr (@Attrs) {
          if ($Attr->nodeName =~ /^.+:(.+)/) { #если атриббут похож на ns

            my $AttrName = $1;
            my $AttrValue =   $NodeAttr->getAttribute($Attr->nodeName);
            #print $Attr->nodeName." || ".$AttrName." || ".$AttrValue."\n";

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

#sub _Unpacker {
#    my $self = shift;
#    print "UNPACK from plugin\n";
#}

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
    $X->Msg("copy $ImgSrcFile -> $ImgDestFile\n","w");
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
        #$Href =~ /^[a-z]+\:\/\// || $Href =~ /^mailto:.+/
        $Href =~ /^[a-zA-Z]+\:/
          ? $Href
          : '#'.($Anchor ? 'link_' : '').$X->Path2ID( ($Link
                                                       ?$Href: #внешний section
                                                       basename($RelPath)."#".$Anchor #текущий section
                                                       ), $RelPath , 'process_href')
        : '';
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
