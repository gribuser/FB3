package FB3::Convert::Epub;

use strict;
use base 'FB3::Convert';
use XML::LibXML;
use File::Basename;
use Clone qw(clone);
use FB3::Euristica;
use utf8;

my %NS = (
  'container' => 'urn:oasis:names:tc:opendocument:xmlns:container',
  'root' => 'http://www.idpf.org/2007/opf',
  'xhtml' => 'http://www.w3.org/1999/xhtml',
  'dc' => 'http://purl.org/dc/elements/1.1/',
);

sub FindFile {
  my $FileName = shift;
  my $Dirs = shift;

  foreach (@$Dirs) {
    my $Path = $_.'/'.$FileName;
    return $Path if -f $Path;
  }
  return undef;
}

sub Reaper {
  my $self = shift;
  my $X = shift;

  unless ($X->{'euristic_skip'}) {
    my $PhantomJS = $X->{'phantom_js_path'} || FindFile('phantomjs', [split /:/,$ENV{'PATH'}]);

    if (-e $PhantomJS) {
      my $EuristicaObj = new FB3::Euristica(verbose => $X->{verbose}, phjs => $PhantomJS);
      $X->{'EuristicaObj'} = $EuristicaObj;
    } else {
      $X->Msg("[SKIP EURISTIC] PhantomJS binary not found. Try --phantomjs=PATH-TO-FILE, --euristic_skip options.\nPhantomJS mus be installed for euristic analize of titles <http://phantomjs.org/>\n",'e');
    }
 
  } else {
    $X->Msg("Skip euristica\n",'w');
  }

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
    'allow_elements_inside' => $FB3::Convert::ElsMainList,
  };
  $AllowElements->{'b'} = {
    'allow_attributes' => ['id'],
    processor => \&TransformTo,
    processor_params => ['strong']
  };
  $AllowElements->{'i'} = {
    'allow_attributes' => ['id'],
    processor => \&TransformTo,
    processor_params => ['em']
  };
  $AllowElements->{'u'} = {
    'allow_attributes' => [],
    processor => \&TransformTo,
    processor_params => ['underline']
  };
  $AllowElements->{'div'} = {
    'exclude_if_inside' => ['div','p','ul','ol','h1','h2','h3','h4','h5','h6','li','pre','table'], #Если div содежрит block-level элементы, мы его чикаем 
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

  
###### счетчики, настройки, аккмуляторы и пр.
  $X->{'MaxMoveCount'} = 100; # максимальное кол-во символов принятия решения пустых <a id="good_link" href=""> на перенос 
  $X->{'EmptyLinksList'} = {}; # список пустых <a id="good_link" href=""> на перенос или превращение
  
##### где хранится содержимое книги
  my $ContainerFile = $Source."/META-INF/container.xml";
  die $self." ".$ContainerFile." not found!" unless -f $ContainerFile;

  $X->Msg("Parse container ".$ContainerFile."\n");
  my $CtDoc = XML::LibXML->load_xml(
    location=>$ContainerFile,
    expand_entities => 0,
    no_network => 1,
    load_ext_dtd => 0
  ) || die "Can't parse file ".$ContainerFile;
  
  my $RootFile = $XC->findnodes('/container:container/container:rootfiles/container:rootfile',$CtDoc)->[0]->getAttribute('full-path');
  die "Can't find full-path attribute in Container [".$NS{'container'}." space]" unless $RootFile;

#### root-файл с описанием контента
  $RootFile = $Source."/".$RootFile;
  die "Can't find root (full-path attribute) file ".$RootFile unless -f $RootFile;

  #Директория, относительно которой лежит контент. Нам с ней еще работать
  $X->{'ContentDir'} = $RootFile;
  $X->{'ContentDir'} =~ s/\/?[^\/]+$//;

  $X->Msg("Parse rootfile ".$RootFile."\n");
  
  my $RootDoc = XML::LibXML->load_xml(
    location => $RootFile,
    expand_entities => 0,
    no_network => 1,
    load_ext_dtd => 0
  ) || die "Can't parse file ".$RootFile;
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
      push @Genres, $self->EncodeUtf8($self->html_trim($Genre->to_literal)),
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
    push @Authors, $self->BuildAuthorName('Unknown') unless scalar @Authors;
    $Description->{'TITLE-INFO'}->{'AUTHORS'} = \@Authors;
  }

  #print Data::Dumper::Dumper($AC);

  #КОНТЕНТ

  my @Pages;
  foreach (@$AC) {
    $X->Msg("Processing in structure: ".$_->{'file'}."\n",'i');
    $X->_bs('c2tree','Контент в дерево согласно схеме');
    push @Pages, $X->Content2Tree($_);
    $X->_be('c2tree');
  }

  # [#01]
  my @PagesComplete;

  #Клеим смежные title
  #Отрезаем ненужное
  
  foreach my $Page (@Pages) {

    $Page->{'content'} = CleanNodeEmptyId($X,$Page->{'content'});
    $Page->{'content'} = CleanEmptyP($X,$Page->{'content'});

    my $c=-1;
    my $EmptyLineDetect=undef;
    my $LastSpace=0;
    foreach my $Item (@{$Page->{'content'}}) {
      $c++;
      next unless defined $Item;
      if (ref $Item eq '' && $Item eq '') {
        $Item=undef;
        next;
      }

      if (ref $Item eq '' && $Item =~ /^[\s\n\r\t]+$/) {
        if ($LastSpace) {
          $Item=undef;
        } else {
          $Item=" ";
        }  
        $LastSpace=1;
        next;
      }
      $LastSpace=0;

      #клеим смежные emptyline
      if (ref $Item eq 'HASH'
          && exists $Item->{'p'}
          && $X->IsEmptyLineValue($Item->{'p'}->{'value'})
        ) {

        if (defined $EmptyLineDetect) {
          push @{$Page->{'content'}->[$EmptyLineDetect]->{p}->{'value'}}, @{$Item->{'p'}->{'value'}};
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
          my $TitleMove = clone($Item->{'title'}->{'value'});
          push @{$Page->{'content'}->[$LastTitleOK]->{'title'}->{'value'}},  @$TitleMove; #переносим title в предыдущий
          delete $Page->{'content'}->[$c];
          delete $Page->{'content'}->[$c-1] #перенос строки тоже грохнем
            if (
              !ref $Page->{'content'}->[$c-1]
              && $X->trim($Page->{'content'}->[$c-1]) eq ''
            );
        }

    }

    #MOVE EMPTY LINKS to title
    for (my $c = scalar @{$Page->{'content'}}; $c>=0; $c--) {
        my $Item = $Page->{'content'}->[$c];
        
        next if (ref $Item ne 'HASH' || !exists $Item->{'title'});

        my @LinksMove2Title;
        for (my $i=$c-1;$i>=0;$i--) { #бежим назад и ищем, нет ли перед нами <a id="some"/>?
          my $Last = $Page->{'content'}->[$i];
          next if !ref($Last) && $X->trim($Last) eq ''; #если перед нами перенос строки, игнорим, ищем <a> дальше
          if (
            ref $Last eq 'HASH'
            && IsEmptyA($Last)
          ) {
            my $Move = delete $Page->{'content'}->[$i];
            my $key = each %$Move; 
            push @LinksMove2Title, $key ne 'a' ? @{$Move->{$key}->{'value'}} : $Move;
          } else {
            last; #наткнулись на НЕ-<a>, хватит перебирать
          }
        }

        if (@LinksMove2Title && ref $Item eq 'HASH' && exists $Item->{'title'}) {
            foreach my $Link (@LinksMove2Title) {
              #занято
              if (exists $Item->{'title'}->{'attributes'}->{'id'} && $Item->{'title'}->{'attributes'}->{'id'}) {
                #тогда будем менять линк на текущий
                $X->{'EmptyLinksList'}->{$Link->{'a'}->{'attributes'}->{'id'}} = $Item->{'title'}->{'attributes'}->{'id'};
              } else {
                #пусто, займем это место! 
                $Item->{'title'}->{'attributes'}->{'id'} = $Link->{'a'}->{'attributes'}->{'id'};
              }

            }
        }
        CleanTitle($X,$Item->{'title'}->{'value'});
    }

    #Clean undef
    my @Push;
    foreach (@{$Page->{'content'}}) {
      next unless defined $_;
      push @Push, $_; 
    }
    $Page->{'content'} = \@Push;
  
    #РИсуем section's
    my @P;
    my $Sec = SectionBody($X);

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
        if (@{$Sec->{'section'}->{'value'}}) {
          my $CloneSec = clone($Sec);
          $CloneSec->{'section'}->{'attributes'}->{'id'} = $X->UUID();
          push @P, clone($CloneSec);
        }
        $Sec->{'section'}->{'value'} = []; #надо закрыть section
        push @{$Sec->{'section'}->{'value'}}, $Item; #и продолжить пушить в новый
        next;
      }

      push @{$Sec->{'section'}->{'value'}}, $Item if $Item;

      if ( #страница закрывается, пушим section что там в нем осталось
        $c >= scalar @{$Page->{'content'}}
      ) {
        my $CloneSec = clone($Sec);
        $CloneSec->{'section'}->{'attributes'}->{'id'} = $X->UUID();
        push @P, $CloneSec;
        $Sec->{'section'}->{'value'} = [];
      }

    }
    pop @{$Page->{'content'}}; #закрывашка

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
    my @PN; #финальная подчистка
    foreach my $Item (@P) {
      next unless defined $Item;
      my $NotEmpty = 0;
      foreach my $String (@{$Item->{'section'}->{'value'}}) {
        $NotEmpty = 1 if defined $String && (ref $String eq 'HASH' || (ref $String eq '' && $X->trim($String) ne ''));
      }
      push @PN, $Item if $NotEmpty;
    }

    if (scalar @PN > 1) {
      $Content = \@PN;
    } elsif (scalar @PN) {
      $Content = $PN[0]->{'section'}->{'value'};  #если section один, то берем только его внутренности, контейнер section лишний 
    }

    if ($Content && @$Content) {
      push @PagesComplete, {ID=>$Page->{'ID'},'content'=>$Content};
    } else {
      $X->Msg("Find empty page. Skip [id: $Page->{'ID'}]\n");      
    }
  
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

  #анализируем и переносим пустые <a> и элементы с несушествующими id
  foreach my $Page (@Body) {
    AnaliseIdEmptyHref($X,$Page->{'section'});
  }
  MoveIdEmptyHref($X,\@Body);
  
  #финальная подчистка
  foreach my $Page (@Body) {
    CleanEmptyP($X,$Page->{'section'}->{'value'});
  }

  $Structure->{'PAGES'} = {
    value => \@Body
  };

}

sub CleanEmptyP {
  my $X = shift;
  my $Data = shift;
  return $Data unless ref $Data eq 'ARRAY';

  #^<p/> и emptyline режем в начале
  foreach my $Item (@$Data) {
    next unless defined $Item;
    if (
        (ref $Item eq 'HASH'
        && exists $Item->{'p'}
        && ( $X->IsEmptyLineValue($Item->{'p'}->{'value'}))
        || !defined $Item || (ref $Item eq '' && $Item =~ /^[\s\t]$/))
      ) {
      $Item=undef;
    } else {
      last;
    }
  }

  #^<p/> и emptyline режем в конце
  foreach my $Item (reverse @$Data) {
    if (
        (ref $Item eq 'HASH'
        && exists $Item->{'p'}
        && ( $X->IsEmptyLineValue($Item->{'p'}->{'value'}))
        || (!defined $Item || (ref $Item eq '' && $Item =~ /^[\s\t]+$/))
           )
      ) {
      $Item = undef;
    } else {
      last;
    }
  }

  #^<p/> и emptyline режем после title
  my $LastTitleOK=0;
  foreach my $Item (@$Data) {

    next unless defined $Item;
    
    if (ref $Item eq 'HASH'
        && exists $Item->{'title'}
    ) {
      $LastTitleOK=1;
      next;
    }

    if ( $LastTitleOK &&
        (ref $Item eq 'HASH'
        && exists $Item->{'p'}
        && ( $X->IsEmptyLineValue($Item->{'p'}->{'value'}))
        || !defined $Item || (ref $Item eq '' && $Item =~ /^[\s\t]$/))
      ) {
      $Item=undef;
    } else {
      $LastTitleOK=0;
      #next;
    }

    if (ref $Item eq 'HASH'
        && exists $Item->{'section'}) {
      $Item->{'section'}->{'value'} = CleanEmptyP($X,$Item->{'section'}->{'value'});
    }

  }
  
  return $Data;
}

sub IsEmptyA {
  my $Data = shift;
  return 0 unless ref $Data eq 'HASH';
  
  return 1 if (
    (
    exists $Data->{'p'}
    && @{$Data->{'p'}->{'value'}} == 1
    && IsEmptyA($Data->{'p'}->{'value'}->[0])
    )
    ||
    (
    exists $Data->{'span'}
    && @{$Data->{'span'}->{'value'}} == 1
    && IsEmptyA($Data->{'span'}->{'value'}->[0])
    )
    ||
    (exists $Data->{'a'}
    && $Data->{'a'}->{'attributes'}->{'xlink:href'} eq ''
    && !@{$Data->{'a'}->{'value'}}
    )
  ); #в <a> ничего нет. Иначе это уже полезный контент, и нечего его в title переносить
  return 0;      
}

sub SectionBody {
  my $X=shift;
  my $Sec = { #заготовка section
    'section' => {
      'value' => [],
      'attributes' => {
        'id' => $X->UUID(),
      }
    }
  };
}
  
# заполняет $X->{'EmptyLinksList'}
# <a id="ID" href=""> ID => newID
sub AnaliseIdEmptyHref {
  my $X = shift;
  my $Data = shift;
  my $Hash4Move = shift;

  return if (ref $Data ne 'HASH' || !exists $Data->{'value'});

  my $First = 0;
  unless ($Hash4Move) {
   $Hash4Move = {
     'count_abs' =>  0, #счетчик от начала секции
     'neighbour' => {}, #счетчик от начала секции - кандидатов, куда можно переносить
     'candidates' => {} #счетчик от начала секции кандидатов на перенос
   };
   $First = 1;
  }

  foreach my $Item (@{$Data->{'value'}}) {

    if (ref $Item eq '') { # это голый текст
      $Hash4Move->{'count_abs'} += length($Item);
    } elsif (ref $Item eq 'HASH') { # это нода

      foreach my $El (keys %$Item) {   
        if ($El eq 'section') {
          AnaliseIdEmptyHref($X,$Item->{$El}); #вложенную секцию обрабатывает как отдельную
        } else {
          if (ref $Item->{$El} eq 'HASH' && exists $Item->{$El}->{'attributes'}->{'id'} && $Item->{$El}->{'attributes'}->{'id'} ne '') {
            if ($El eq 'a' && exists $Item->{$El}->{'attributes'}->{'xlink:href'} && $Item->{$El}->{'attributes'}->{'xlink:href'} eq '') {
              #ссылка - кандидат на перенос
              $Hash4Move->{'candidates'}->{$Item->{$El}->{'attributes'}->{'id'}} = $Hash4Move->{'count_abs'};
            } else {
              #кандидат, куда можно перенести ссылку
              $Hash4Move->{'neighbour'}->{$Item->{$El}->{'attributes'}->{'id'}} = $Hash4Move->{'count_abs'};
            }
          }
          AnaliseIdEmptyHref($X,$Item->{$El},$Hash4Move);
        }
      }
    
    }

  }
  
  if ($First) {
    #анализируем и собираем элементы для переноса или превращения
    foreach my $Cand (keys %{$Hash4Move->{'candidates'}}) {
    
      if ( $Hash4Move->{'candidates'}->{$Cand} <= $X->{'MaxMoveCount'} ) {
        #переносим в id секции
        $X->{'EmptyLinksList'}->{$Cand} = $Data->{'attributes'}->{'id'};
      } else {
        #вычислим ближайшего соседа для переноса
        my %Sort = ();
        foreach (keys %{$Hash4Move->{'neighbour'}}) {
          $Sort{$_} = abs($Hash4Move->{'candidates'}->{$Cand} - $Hash4Move->{'neighbour'}->{$_});
        }
        my $MinNeigh = [sort {$Sort{$a} <=> $Sort{$b}} keys %Sort]->[0];
        $X->{'EmptyLinksList'}->{$Cand} = $MinNeigh if (%Sort && $Sort{$MinNeigh} <= $X->{'MaxMoveCount'});
      }
      #иначе отдаем на превращение
      $X->{'EmptyLinksList'}->{$Cand} = 'rename' if !exists $X->{'EmptyLinksList'}->{$Cand} || !defined $X->{'EmptyLinksList'}->{$Cand};
    }
  }
  
}

sub MoveIdEmptyHref {
  my $X = shift;
  my $Data = shift;
  return unless ref $Data eq 'ARRAY';

  foreach my $Item (@$Data) {
    next unless ref $Item eq 'HASH';
    foreach my $ElName (keys %$Item) {
      my $El = $Item->{$ElName};
      next unless ref $El eq 'HASH';
      #меняем ссылку
      if (
        $X->{'EmptyLinksList'}->{ $X->CutLinkDiez($El->{'attributes'}->{'xlink:href'}) } ne 'rename'
        && exists $El->{'attributes'}
        && exists $El->{'attributes'}->{'xlink:href'}
        && exists $X->{'EmptyLinksList'}->{ $X->CutLinkDiez($El->{'attributes'}->{'xlink:href'}) }
      ) {
        $El->{'attributes'}->{'xlink:href'} = "#".$X->{'EmptyLinksList'}->{ $X->CutLinkDiez($El->{'attributes'}->{'xlink:href'}) };
        $X->Msg("Empty link move to neighbour id $El->{'attributes'}->{'xlink:href'} [".($X->{'id_list'}->{$X->CutLinkDiez($El->{'attributes'}->{'xlink:href'})}||'section')."]\n","w");
      }
      #удаляем элемент со старым id либо превращаем в span, если нет кандидатов на перенос
      if (
          exists $El->{'attributes'}
          && exists $El->{'attributes'}->{'id'}
          && exists $X->{'EmptyLinksList'}->{ $El->{'attributes'}->{'id'} }
      ) {
        if ($X->{'EmptyLinksList'}->{ $El->{'attributes'}->{'id'} } eq 'rename') {
          $Item = $El->{'value'} = {'span'=>{'value'=>$El->{'value'},'attributes'=>{'id'=>$El->{'attributes'}->{'id'}}}}; #-> span
          $X->Msg("Empty link rename to <span> [".$X->{'id_list'}->{$El->{'attributes'}->{'id'}}."]\n","w");
        } else {
          $Item = $El->{'value'}; #удаляем
        }
      }
      MoveIdEmptyHref($X,$El->{'value'});
    }
  }

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
  my @CssList;
  foreach my $Item (@$Manifest) {
    $Ind++;
    $ReverseManifest{$Item->{'id'}} = $Item;

    # !! Стили пока не трогаем !!
    if ($Item->{'type'} =~ /^text\/css$/) { # В манифесте css 
    #  push @{$X->{'STRUCTURE'}->{'CSS_LIST'}}, {
    #    'src_path' => $Item->{'href'},
    #    'new_path' => undef,
    #    'id' => $Item->{'id'},
    #  };
      push @CssList, $X->{'ContentDir'}.'/'.$Item->{'href'}; #для анализатора все-таки соберем
     ## File::Copy::copy($X->{'ContentDir'}.'/'.$Item->{'href'}, '/tmp/1/'.rand(10000)) or die $!;
    }

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

      if ($X->{'EuristicaObj'}) {
        $X->_bs('euristic','Эвристический анализ заголовка');
        my $Euristica = $X->{'EuristicaObj'}->ParseFile('file'=>$ContentFile, 'css_list' => \@CssList);
        if ($Euristica->{'CHANGED'}) {
         ## open my $FS,">:utf8",$ContentFile;
         ## print $FS $Euristica->{'CONTENT'};
         ## close $FS;
        }
        $X->_be('euristic');
       ## if ($Euristica->{'CHANGED'}) { #DEBUG
       ##   $X->{FND} = 1 unless exists $X->{FND};
       ##   my $FND = $X->{FND}++;
       ##   ##print Data::Dumper::Dumper($Euristica);
       ##   File::Copy::copy($ContentFile, '/tmp/1/'.$X->{FND});
          
       ##   open F,">:utf8","/tmp/1/".$X->{FND}.".cng";
       ##   print F $Euristica->{'CONTENT'};
       ##   close F;
       ## }
      }



      $X->Msg("Parse content file ".$ContentFile."\n");

      $X->_bs('parse_epub_xhtml', 'xml-парсинг файлов epub [Открытие, первичные преобразования, парсинг]');
      my $Content;
      open my $FO,"<".$ContentFile;
      map {$Content.=$_} <$FO>;
      close $FO;
 
      $X->_bs('Entities', 'Преобразование Entities');
      $Content = $X->qent(Encode::decode_utf8($Content));
      $X->_be('Entities');

      $X->Msg("Fix strange text\n");
      $Content = $X->ShitFix($Content);

      $X->Msg("Parse XML\n");
      my $ContentDoc = XML::LibXML->load_xml(
        string => $Content,
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

      $X->_be('parse_epub_xhtml');

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
      next if ref $Item->{$El} ne 'HASH' || !exists $Item->{$El}->{'value'};
      $Item->{$El}->{'value'} = CleanNodeEmptyId($X,$Item->{$El}->{'value'});
      if (exists $Item->{$El}->{'attributes'}->{'id'} || $El =~ /^(a|span)$/) {
        my $Id = exists $Item->{$El}->{'attributes'}->{'id'} ? $Item->{$El}->{'attributes'}->{'id'} : '';
        if (!exists $X->{'href_list'}->{"#".$Id} || !$Id) { #элементы с несуществующими id
          
          my $Link;
          $Link = $X->trim($Item->{$El}->{'attributes'}->{'xlink:href'})if exists $Item->{$El}->{'attributes'}->{'xlink:href'};
          
          if ($Id) {
            $X->Msg("Find non exists ID and delete '$Id' in node '$El' [".$X->{'id_list'}->{$Id}."]\n","w");
            delete $Item->{$El}->{'attributes'}->{'id'}; #удалим id
          } elsif ($Link eq '') {
            $X->Msg("Find node '$El' without id\n","w");
          }
          
          next unless $El =~ /^(a|span)$/;
          if ($El eq 'a' && $Link ne '') { #<a> c линками оставим
            $X->Msg("Find link [$Link]. Skip\n","w");
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
    $X->_bs('img_copy','Копирование IMG');
    FB3::Convert::copy($ImgSrcFile, $ImgDestFile) or $X->Error($!." [copy $ImgSrcFile -> $ImgDestFile]");        
    $X->_be('img_copy','Копирование IMG');
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

  $Href = $X->trim_soft($Href);
  my ($Link, $Anchor) = split /\#/, $Href, 2;

  my $NewHref =
  $Href ?
        $Href =~ /^[a-z]+\:/i
          ? $X->CorrectOuterLink($Href)
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

  my $NewNode = XML::LibXML::Element->new('title');
  foreach ($Node->getAttributes) { #скопируем атрибуты
    $NewNode->setAttribute($_->name => $_->value);
  }

  my $Wrap = XML::LibXML::Element->new("p"); #wrapper
  foreach my $Child ($Node->getChildnodes) {
    $Wrap->addChild($Child->cloneNode(1));
  }
 
  $NewNode->addChild($Wrap);

  return $NewNode;
}

1;
