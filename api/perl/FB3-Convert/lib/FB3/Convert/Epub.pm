package FB3::Convert::Epub;

use strict;
use base 'FB3::Convert';
use XML::LibXML;
use File::Basename;
use Image::ExifTool qw(:Public);
use Image::Size;
use Clone qw(clone);
use FB3::Euristica;
use URI::Escape;
use utf8;

my %NS = (
  'container' => 'urn:oasis:names:tc:opendocument:xmlns:container',
  'root' => 'http://www.idpf.org/2007/opf',
  'xhtml' => 'http://www.w3.org/1999/xhtml',
  'dc' => 'http://purl.org/dc/elements/1.1/',
);

my $XC = XML::LibXML::XPathContext->new();

my %GenreTranslate = (
  'accounting'=>'Бухучет, налогообложение, аудит',
  'adventure'=>'Приключения',
  'adv_animal'=>'Природа и животные',
  'adv_geo'=>'Книги о Путешествиях',
  'adv_history'=>'Исторические приключения',
  'adv_maritime'=>'Морские приключения',
  'adv_western'=>'Вестерны',
  'antique'=>'Старинная литература',
  'antique_ant'=>'Античная литература',
  'antique_east'=>'Древневосточная литература',
  'antique_european'=>'Европейская старинная литература',
  'antique_myths'=>'Мифы. Легенды. Эпос',
  'antique_russian'=>'Древнерусская литература',
  'aphorism_quote'=>'Афоризмы и цитаты',
  'architecture_book'=>'Архитектура',
  'auto_regulations'=>'Автомобили и ПДД',
  'banking'=>'Банковское дело',
  'beginning_authors'=>'Начинающие авторы',
  'samizdat'=>'Самиздат',
  'children'=>'Книги для детей',
  'child_adv'=>'Детские приключения',
  'child_det'=>'Детские детективы',
  'child_education'=>'Учебная литература',
  'child_prose'=>'Детская проза',
  'child_sf'=>'Детская фантастика',
  'child_tale'=>'Сказки',
  'child_verse'=>'Детские стихи',
  'cinema_theatre'=>'Кинематограф, театр',
  'city_fantasy'=>'Городское фэнтези',
  'computers'=>'Компьютеры',
  'comp_db'=>'Базы данных',
  'comp_hard'=>'Компьютерное Железо',
  'comp_osnet'=>'ОС и Сети',
  'comp_programming'=>'Программирование',
  'comp_soft'=>'Программы',
  'comp_www'=>'Интернет',
  'detective'=>'Современные детективы',
  'det_action'=>'Боевики',
  'det_classic'=>'Классические детективы',
  'det_crime'=>'Криминальные боевики',
  'det_espionage'=>'Шпионские детективы',
  'det_hard'=>'Крутой детектив',
  'det_history'=>'Исторические детективы',
  'det_irony'=>'Иронические детективы',
  'det_police'=>'Полицейские детективы',
  'det_political'=>'Политические детективы',
  'dragon_fantasy'=>'Фэнтези про драконов',
  'dramaturgy'=>'Драматургия',
  'economics'=>'Экономика',
  'essays'=>'Эссе',
  'fantasy_fight'=>'Боевое фэнтези',
  'foreign_action'=>'Зарубежные боевики',
  'foreign_adventure'=>'Зарубежные приключения',
  'foreign_antique'=>'Зарубежная старинная литература',
  'foreign_business'=>'Зарубежная деловая литература',
  'foreign_children'=>'Зарубежные детские книги',
  'foreign_comp'=>'Зарубежная компьютерная литература',
  'foreign_contemporary'=>'Современная зарубежная литература',
  'foreign_desc'=>'Зарубежная справочная литература',
  'foreign_detective'=>'Зарубежные детективы',
  'foreign_dramaturgy'=>'Зарубежная драматургия',
  'foreign_edu'=>'Зарубежная образовательная литература',
  'foreign_fantasy'=>'Зарубежное фэнтези',
  'foreign_home'=>'Зарубежная прикладная и научно-популярная литература',
  'foreign_humor'=>'Зарубежный юмор',
  'foreign_language'=>'Иностранные языки',
  'foreign_love'=>'Зарубежные любовные романы',
  'foreign_other'=>'Зарубежное',
  'foreign_poetry'=>'Зарубежные стихи',
  'foreign_prose'=>'Зарубежная классика',
  'foreign_psychology'=>'Зарубежная психология',
  'foreign_publicism'=>'Зарубежная публицистика',
  'foreign_religion'=>'Зарубежная эзотерическая и религиозная литература',
  'foreign_sf'=>'Зарубежная фантастика',
  'geography_book'=>'География',
  'geo_guides'=>'Путеводители',
  'global_economy'=>'ВЭД',
  'historical_fantasy'=>'Историческое фэнтези',
  'home'=>'Дом и Семья',
  'home_cooking'=>'Кулинария',
  'home_crafts'=>'Хобби, Ремесла',
  'home_diy'=>'Сделай Сам',
  'home_entertain'=>'Развлечения',
  'home_garden'=>'Сад и Огород',
  'home_health'=>'Здоровье',
  'home_pets'=>'Домашние Животные',
  'home_sex'=>'Эротика, Секс',
  'home_sport'=>'Спорт, фитнес',
  'humor'=>'Юмор',
  'humor_anecdote'=>'Анекдоты',
  'humor_fantasy'=>'Юмористическое фэнтези',
  'humor_prose'=>'Юмористическая проза',
  'humor_verse'=>'Юмористические стихи',
  'industries'=>'Отраслевые издания',
  'job_hunting'=>'Поиск работы, карьера',
  'literature_18'=>'Литература 18 века',
  'literature_19'=>'Литература 19 века',
  'literature_20'=>'Литература 20 века',
  'love_contemporary'=>'Современные любовные романы',
  'love_detective'=>'Остросюжетные любовные романы',
  'love_erotica'=>'Эротическая литература',
  'love_fantasy'=>'Любовное фэнтези',
  'love_history'=>'Исторические любовные романы',
  'love_sf'=>'Любовно-фантастические романы',
  'love_short'=>'Короткие любовные романы',
  'magician_book'=>'Книги про волшебников',
  'management'=>'Управление, подбор персонала',
  'marketing'=>'Маркетинг, PR, реклама',
  'military_special'=>'Военное дело, спецслужбы',
  'music_dancing'=>'Музыка, балет',
  'narrative'=>'Повести',
  'newspapers'=>'Газеты',
  'nonfiction'=>'Документальная литература',
  'nonf_biography'=>'Биографии и Мемуары',
  'nonf_criticism'=>'Критика',
  'nonf_publicism'=>'Публицистика',
  'org_behavior'=>'Корпоративная культура',
  'paper_work'=>'Делопроизводство',
  'pedagogy_book'=>'Педагогика',
  'periodic'=>'Журналы',
  'personal_finance'=>'Личные финансы',
  'poetry'=>'Поэзия',
  'popadanec'=>'Попаданцы',
  'popular_business'=>'О бизнесе популярно',
  'prose_classic'=>'Классическая проза',
  'prose_counter'=>'Контркультура',
  'prose_history'=>'Историческая литература',
  'prose_military'=>'Книги о войне',
  'prose_rus_classic'=>'Русская классика',
  'prose_su_classics'=>'Советская литература',
  'psy_alassic'=>'Классики психологии',
  'psy_childs'=>'Детская психология',
  'psy_generic'=>'Общая психология',
  'psy_personal'=>'Личностный рост',
  'psy_sex_and_family'=>'Секс и семейная психология',
  'psy_social'=>'Социальная психология',
  'psy_theraphy'=>'Психотерапия и консультирование',
  'real_estate'=>'Недвижимость',
  'reference'=>'Справочная литература',
  'ref_dict'=>'Словари',
  'ref_encyc'=>'Энциклопедии',
  'ref_guide'=>'Руководства',
  'ref_ref'=>'Справочники',
  'religion'=>'Религия',
  'religion_esoterics'=>'Эзотерика',
  'religion_rel'=>'Религиозные тексты',
  'religion_self'=>'Самосовершенствование',
  'russian_contemporary'=>'Современная русская литература',
  'russian_fantasy'=>'Русское фэнтези',
  'science'=>'Прочая образовательная литература',
  'sci_biology'=>'Биология',
  'sci_chem'=>'Химия',
  'sci_culture'=>'Культурология',
  'sci_history'=>'История',
  'sci_juris'=>'Юриспруденция, право',
  'sci_linguistic'=>'Языкознание',
  'sci_math'=>'Математика',
  'sci_medicine'=>'Медицина',
  'sci_philosophy'=>'Философия',
  'sci_phys'=>'Физика',
  'sci_politics'=>'Политика, политология',
  'sci_religion'=>'Религиоведение',
  'sci_tech'=>'Техническая литература',
  'sf'=>'Научная фантастика',
  'sf_action'=>'Боевая фантастика',
  'sf_cyberpunk'=>'Киберпанк',
  'sf_detective'=>'Детективная фантастика',
  'sf_heroic'=>'Героическая фантастика',
  'sf_history'=>'Историческая фантастика',
  'sf_horror'=>'Ужасы и Мистика',
  'sf_humor'=>'Юмористическая фантастика',
  'sf_social'=>'Социальная фантастика',
  'sf_space'=>'Космическая фантастика',
  'short_story'=>'Рассказы',
  'sketch'=>'Очерки',
  'small_business'=>'Малый бизнес',
  'sociology_book'=>'Социология',
  'stock'=>'Ценные бумаги, инвестиции',
  'thriller'=>'Триллеры',
  'upbringing_book'=>'Воспитание детей',
  'vampire_book'=>'Книги про вампиров',
  'visual_arts'=>'Изобразительное искусство, фотография',
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

  my %Args = @_;
  my $Source = $Args{'source'} || $X->Error("Source path not defined");
  my $XC = XML::LibXML::XPathContext->new();

  $XC->registerNs('container', $NS{'container'});
  $XC->registerNs('root', $NS{'root'});
  $XC->registerNs('dc', $NS{'dc'});

  my $AllowElements = $X->{'allow_elements'};
### Обработчики нод для epub
  $AllowElements->{'img'} = {
    'allow_attributes' => ['src','id','alt'
      #,'width',#пока не подготовлен
    ],
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
  $AllowElements->{'br'} = { #мы его потом превратим в параграф
  };
  $AllowElements->{'u'} = {
    'allow_attributes' => [],
    processor => \&TransformTo,
    processor_params => ['underline']
  };
  $AllowElements->{'div'} = {
    'exclude_if_inside' => ['div','p','ul','ol','h1','h2','h3','h4','h5','h6','li','pre','table','section'], #Если div содежрит block-level элементы, мы его чикаем 
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

  my $Structure = $X->{'STRUCTURE'};
  my $Description = $Structure->{'DESCRIPTION'};
  
###### счетчики, настройки, аккмуляторы и пр.
  $X->{'MaxMoveCount'} = 100; # максимальное кол-во символов принятия решения пустых <a id="good_link" href="bad_link"> на перенос 
  $X->{'EmptyLinksList'} = {}; # список пустых <a id="good_link" href=""> на перенос или превращение
  
##### где хранится содержимое книги
  my $ContainerFile = $Source."/META-INF/container.xml";
  $X->Error($self." ".$ContainerFile." not found!") unless -f $ContainerFile;

  $X->Msg("Parse container ".$ContainerFile."\n");
  my $CtDoc = XML::LibXML->load_xml(
    location=>$ContainerFile,
    expand_entities => 0,
    no_network => 1,
    load_ext_dtd => 0
  ) || $X->Error("Can't parse file ".$ContainerFile);
  
  my $RootFile = $XC->findnodes('/container:container/container:rootfiles/container:rootfile',$CtDoc)->[0]->getAttribute('full-path');
  $X->Error("Can't find full-path attribute in Container [".$NS{'container'}." space]") unless $RootFile;

#### root-файл с описанием контента
  $RootFile = $Source."/".$RootFile;
  $X->Error("Can't find root (full-path attribute) file ".$RootFile) unless -f $RootFile;

  #Директория, относительно которой лежит контент. Нам с ней еще работать
  $X->{'ContentDir'} = $RootFile;
  $X->{'ContentDir'} =~ s/\/?[^\/]+$//;

  if ($X->{'euristic'}) {
    $X->Msg("Euristica enabled\n",'w');

    my $PhantomJS = $X->{'phantom_js_path'} || FindFile('phantomjs', [split /:/,$ENV{'PATH'}]);

    if (-e $PhantomJS) {
      my $EuristicaObj = new FB3::Euristica(
        'verbose' => $X->{verbose},
        'phjs' => $PhantomJS,
        'ContentDir' => $X->{'ContentDir'},
        'SourceDir' => $X->{'SourceDir'},
        'DestinationDir' => $X->{'DestinationDir'},
        'DebugPath' => $X->{'euristic_debug'},
        'DebugPrefix' => $X->{'SourceFileName'},
        'unzipped' => $X->{'unzipped'},
      );
      $X->{'EuristicaObj'} = $EuristicaObj;
    } else {
      $X->Msg("[SKIP EURISTIC] PhantomJS binary not found. Try --phantomjs=PATH-TO-FILE, --euristic_skip options.\nPhantomJS mus be installed for euristic analize of titles <http://phantomjs.org/>\n",'e');
    }
 
  }

  $X->Msg("Parse rootfile ".$RootFile."\n");
  
  my $RootDoc = XML::LibXML->load_xml(
    location => $RootFile,
    expand_entities => 0,
    no_network => 1,
    load_ext_dtd => 0
  ) || $X->Error("Can't parse file ".$RootFile);
  $RootDoc->setEncoding('utf-8');

  #ИЩЕМ Cover
  my $CoverImg;
  my $CheckIsCover=0;

  #согласно epub.3 может быть в <item properties="cover-image"
  if (my $CoverNode = $XC->findnodes('/root:package/root:manifest/root:item[@properties="cover-image"]',$RootDoc)->[0]) {
    if ($CoverNode->getAttribute('media-type') =~ /^image\/(jpeg|png)$/) {
      if ($CoverNode->getAttribute('href')) {
        $CoverImg = $CoverNode->getAttribute('href');
      }
    }
  }

  #согласно epub.2 может быть в <meta name="cover"
  if ( !$CoverImg && (my $CoverNode = $XC->findnodes('/root:package/root:metadata/root:meta[@name="cover"]',$RootDoc)->[0]) ) {
    my $CoverID = $CoverNode->getAttribute('content');
    if (my $CoverItem = $XC->findnodes('/root:package/root:manifest/root:item[@id="'.$CoverID.'"]',$RootDoc)->[0]) {
      if ($CoverItem->getAttribute('media-type') =~ /^image\/(jpeg|png)$/) {
        if ($CoverItem->getAttribute('href')) {
          $CoverImg = $CoverItem->getAttribute('href');
        }
      }
    }
  }

  # список файлов с контентом
  my @Manifest;
  for my $MItem ($XC->findnodes('/root:package/root:manifest/root:item',$RootDoc)) {
    my $ItemHref = $MItem->getAttribute('href');
    my $ItemType = $MItem->getAttribute('media-type');
    push @Manifest, {
      'id' => $MItem->getAttribute('id'),
      'href' => $ItemHref,
      'type' => $ItemType,
    };

    if ( # обложка не найдена? попробуем сами поискать
      !$CoverImg
      && $ItemHref =~ /cover/i
      && $ItemType =~ /^image\/(jpeg|png)$/
    ) { 
      $CheckIsCover = 1; #способ хулиганский, поэтому будем проверять картинку
      $CoverImg = $ItemHref;
    }

  }
  my @Spine;
  for my $MItem ($XC->findnodes('/root:package/root:spine/root:itemref',$RootDoc)) {
    my $IdRef = $MItem->getAttribute('idref');
    push @Spine, $IdRef;
  }

  if ($CoverImg) {
    $X->Msg("Try process cover image '$CoverImg'\n");
   
    my $SkipExists = 1;
     my $CoverSrcFile = $X->RealPath(
      FB3::Convert::dirname(
        $X->{'ContentDir'}.'/'.$CoverImg
      ).'/'.FB3::Convert::basename($CoverImg),
    undef, $SkipExists);

    $CoverSrcFile = CheckIsCover($X,$CoverSrcFile) if $CheckIsCover;

    if (-f $CoverSrcFile) {
      my $ImgList = $X->{'STRUCTURE'}->{'IMG_LIST'};
      my $CoverDestPath = $X->{'DestinationDir'}."/fb3/img";

      $CoverImg =~ /.([^\/\.]+)$/;
      my $ImgType = $1;

      my $ImgID = 'img_'.$X->UUID($CoverSrcFile);
      my $NewFileName = $ImgID.'.'.$ImgType;
      my $CoverDestFile = $CoverDestPath.'/'.$NewFileName;

      my $CoverDesc = {
        'src_path' => $CoverSrcFile,
        'new_path' => "img/".$NewFileName, #заменим на новое имя
        'id' => $ImgID,
      };

      push @$ImgList, $CoverDesc unless grep {$_->{id} eq $ImgID} @$ImgList;
      $Structure->{'DESCRIPTION'}->{'TITLE-INFO'}->{'COVER_DESC'} = $CoverDesc;

      #Копируем исходник на новое место с новым уникальным именем
      unless (-f $CoverDestFile) {
        $X->Msg("copy $CoverSrcFile -> $CoverDestFile\n");
        FB3::Convert::copy($CoverSrcFile, $CoverDestFile) or $X->Error($!." [copy $CoverSrcFile -> $CoverDestFile]");        
       }
      $X->Msg("Cover '$CoverImg' is OK\n");
    }

  }
  #/cover

  $X->Msg("Assemble content\n");
  my $AC = AssembleContent($X, 'manifest' => \@Manifest, 'spine' => \@Spine);
  # Отдаем контент на обработку

  #Заполняем внутренний формат

  #МЕТА
  my $GlobalID;  
  unless (defined $Description->{'DOCUMENT-INFO'}->{'ID'}) { 
    $Description->{'DOCUMENT-INFO'}->{'ID'} = $GlobalID = $X->UUID();
  }

  unless (defined $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'}) {
    my $Lang = $XC->findnodes('/root:package/root:metadata/dc:language',$RootDoc)->[0];
    $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'} = $self->html_trim($Lang->to_literal) if $Lang;

    unless ($Description->{'DOCUMENT-INFO'}->{'LANGUAGE'}) {
      my $TextForIdent = FetchText4Ident($AC,500);
      $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'} = $X->GuessLang($TextForIdent);
      $Description->{'DOCUMENT-INFO'}->{'LANGUAGE'} ||= 'en';
    }
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

  ##print Data::Dumper::Dumper($AC);

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

    $c=0;
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

        my $ValNode = $Sec->{'section'}->{'value'}->[0]->{'title'}->{'value'}->[0];
        $Sec->{'section'}->{'value'} = 
          [
           {
            'subtitle' => {
             'value' => (ref $ValNode eq 'HASH' ? $ValNode->{'p'}->{'value'} : $ValNode),
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

sub FetchText4Ident {
  my $Data = shift;
  my $MinLen = shift || 200;
  my $Text;

  foreach (@$Data) {
    my $Content = $_->{'content'};
    $Content =~ s/<.*>//g;
    $Content =~ s/[\n\r]/ /g;
    $Content =~ s/^\s*//;
    $Content =~ s/\s*$//;
    $Content =~ s/\s+/ /g;
    $Content =~ s/[\{\}\\\(\)\/0-9\[\]]+//g;
    $Content =~ s/\s+\././g;
    $Content =~ s/,\./,/g;
    $Content =~ s/\.+/./g;

    $Text .= (length($Text)?' ':'').$Content;
    return $Text if length($Text) >= $MinLen;
  }

  return $Text;
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

  $Data->{'value'} = [$Data->{'value'}] unless ref $Data->{'value'} eq 'ARRAY';

  foreach my $Item (@{$Data->{'value'}}) {

    if (ref $Item eq '') { # это голый текст
      $Hash4Move->{'count_abs'} += length($Item);
    } elsif (ref $Item eq 'HASH') { # это нода

      foreach my $El (keys %$Item) {   
        if ($El eq 'section') {
          AnaliseIdEmptyHref($X,$Item->{$El}); #вложенную секцию обрабатывает как отдельную
        } else {
          if (ref $Item->{$El} eq 'HASH' && exists $Item->{$El}->{'attributes'}->{'id'} && $Item->{$El}->{'attributes'}->{'id'} ne '') {
            if ($El eq 'a' && exists $Item->{$El}->{'attributes'}->{'xlink:href'}
             && ( #пустая или кривая ссылка - кандидат на переезд
               $Item->{$El}->{'attributes'}->{'xlink:href'} eq ''
               || ( $Item->{$El}->{'attributes'}->{'xlink:href'} =~ /^#/ && !exists $X->{'id_list'}->{ $X->CutLinkDiez($Item->{$El}->{'attributes'}->{'xlink:href'}) } )
              )
             ) {
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

  my @Files4Eur;
  if ($X->{'EuristicaObj'}) { #придется собрать файлы для эвристики отдельно. нужно будет объединить с обработкой
    for my $ItemID (@$Spine) {
      my $Item = $ReverseManifest{$ItemID};
      if ($Item->{'type'} =~ /^application\/xhtml/) {
        my $ContentFile = $X->{'ContentDir'}.'/'.$Item->{'href'};
        $ContentFile =~ s/%20/ /g;
        push @Files4Eur, $ContentFile;
      }
    }
    $X->Msg("Calculate all links for euristica\n");
    $X->_bs('EuristicLinks','Калькуляция всех локальных ссылок для эвристики');
    $X->{'EuristicaObj'}->CalculateLinks('files'=>\@Files4Eur);
    $X->_be('EuristicLinks');
  }

  #бежим по списку, составляем скелет контекстной части
  for my $ItemID (@$Spine) {
    my $Item = $ReverseManifest{$ItemID};

    if (!exists $ReverseManifest{$ItemID}) {
      $X->Msg("id ".$ItemID." not exists in Manifest list\n",'i');
      next;
    }

    if ($Item->{'type'} =~ /^application\/xhtml/) { # Видимо, текст

      my $ContentFile = $X->{'ContentDir'}.'/'.$Item->{'href'};
      $ContentFile = uri_unescape($ContentFile);

      $X->Msg("Fix strange text\n");
      $X->_bs('Strange', 'Зачистка странностей');
      $X->ShitFixFile($ContentFile);
      $X->_be('Strange');

      if ($X->{'EuristicaObj'}) {
        $X->Msg("Euristic analize ".$ContentFile."\n");
        $X->_bs('euristic','Эвристический анализ заголовка');
        my $Euristica = $X->{'EuristicaObj'}->ParseFile('file'=>$ContentFile);
        #print Data::Dumper::Dumper($Euristica);
        
        #пишем контент из эвристики на место
        ##if ($Euristica->{'CHANGED'}
        ##) {
          open my $FS,">:utf8",$ContentFile;
          print $FS $Euristica->{'CONTENT'};
          close $FS;
        ##} 
        $X->_be('euristic');

      }

      $X->Msg("Parse content file ".$ContentFile."\n");

      $X->_bs('parse_epub_xhtml', 'xml-парсинг файлов epub [Открытие, первичные преобразования, парсинг]');
      my $Content;
      open my $FO,"<".$ContentFile or $X->Error("can't open file $ContentFile $!");
      map {$Content.=$_} <$FO>;
      close $FO;

      $X->_bs('Entities', 'Преобразование Entities');
      $Content = $X->qent(Encode::decode_utf8($Content));
      $X->_be('Entities');

      #phantomjs нам снова наследил
      if ($X->{'EuristicaObj'}) {
        $Content = $X->MetaFix($Content); 
        $Content = $X->SomeFix($Content); 
      }

      $X->Msg("Parse XML\n");
      my $ContentDoc = XML::LibXML->load_xml(
        string => $Content,
        expand_entities => 0, # не считать & за entity
        no_network => 1, # не будем тянуть внешние вложения
        recover => 2, # => 0 - падать при кривой структуре. например, не закрыт тег. entity и пр | => 1 - вопить, 2 - совсем молчать
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

      $Content = $X->InNode($Body);
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

sub CheckIsCover {
  my $X = shift;
  my $ImgSrcFile = shift;

  my $ImgInfo = [Image::Size::imgsize($ImgSrcFile)];
  my $W = $ImgInfo->[0] || return;
  my $H = $ImgInfo->[1] || return;

  my $Prop = $H/$W;
  #img должен быть 1:1 - 1:5 и ширина 200+
  return unless ($W>=200 && $Prop >=1 && $Prop <=5);
  return $ImgSrcFile;
}

sub CleanTitle {
  my $X = shift;
  my $Node = shift;

  return $Node unless ref $Node eq 'ARRAY';

  foreach my $Item (@$Node) {
    $Item = undef
      if ref $Item eq 'HASH' && exists $Item->{'p'} &&
      ( 
        (
        ref $Item->{'p'}->{'value'} eq 'ARRAY' && !scalar @{$Item->{'p'}->{'value'}}
        || !grep {$_ =~ /[^\s\t]+/} @{$Item->{'p'}->{'value'}}
        )
        || $Item->{'p'}->{'value'} =~ /^[\s\t]*$/
      );  

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
  my $IdsCollect = shift || {};

  return $Node unless ref $Node eq 'ARRAY';

  my $Ret = [];

  foreach my $Item (@$Node) {
    push @$Ret, $Item;
    next unless ref $Item eq 'HASH';
    foreach my $El (keys %$Item) {
      next if ref $Item->{$El} ne 'HASH' || !exists $Item->{$El}->{'value'};
      $Item->{$El}->{'value'} = CleanNodeEmptyId($X,$Item->{$El}->{'value'},$IdsCollect);
      if (exists $Item->{$El}->{'attributes'}->{'id'} || $El =~ /^(a|span)$/) {
        my $Id = exists $Item->{$El}->{'attributes'}->{'id'} ? $Item->{$El}->{'attributes'}->{'id'} : '';

        if (!exists $X->{'href_list'}->{"#".$Id} || !$Id || exists $IdsCollect->{$Id}) { #элементы с несуществующими id
          my $Link;
          $Link = $X->trim($Item->{$El}->{'attributes'}->{'xlink:href'}) if exists $Item->{$El}->{'attributes'}->{'xlink:href'};
          
          if ($Id) {
            if (exists $IdsCollect->{$Id}) {
              $X->Msg("Find double ID and delete '$Id' in node '$El'\n","w");
            } else {
              $X->Msg("Find non exists ID and delete '$Id' in node '$El' [".$X->{'id_list'}->{$Id}."]\n","w");
            }
            delete $Item->{$El}->{'attributes'}->{'id'}; #удалим id
          } elsif ($Link eq '') {
            $X->Msg("Find node '$El' without id\n","w");
          }

          next unless $El =~ /^(a|span)$/;
          #<a> c действующими линками оставим
          if ($El eq 'a' && $Link ne ''
            && (
              $Link !~ /^#link_/ #только ссылки внутри section нам интересны
              || exists $X->{'id_list'}->{$X->CutLinkDiez($Link)} #ссылка живая
            )
          ) {
            $X->Msg("Find link [$Link]. Skip\n","w");
            next;
          }
          pop @$Ret;
          push @$Ret, @{$Item->{$El}->{'value'}} if scalar @{$Item->{$El}->{'value'}}; #переносим на место ноды ее внутренности
          $X->Msg("Delete node '$El'\n");
        }
        $IdsCollect->{$Id}++;
      }
    }
  }

  return $Ret;
}

#Процессоры обработки нод

# Копируем картинки, перерисовывает атрибуты картинок на новые
my %ImgChecked;
sub ProcessImg {
  my $X = shift;
  my %Args = @_;
  my $Node = $Args{'node'};
  my $RelPath = $Args{'relpath'};

  my $ImgList = $X->{'STRUCTURE'}->{'IMG_LIST'};
  my $Src = $Node->getAttribute('src');

  unless ($Src) {
    $X->Msg("Can't find img src. Remove img\n","w");
    my $Doc = XML::LibXML::Document->new('1.0', 'utf-8');
    my $Text = $Doc->createTextNode('');
    return $Text;
  }

  #честный абсолютный путь к картинке
  my $SkipExists = 1; #не падать, если файл отсутствует
  my $ImgSrcFile = $X->RealPath(
    FB3::Convert::dirname($X->RealPath( $RelPath ? $X->{'ContentDir'}.'/'.$RelPath : $X->{'ContentDir'}, undef, $SkipExists)).'/'.$Src,
  undef,$SkipExists);

  my $CoverIxists = $X->{'STRUCTURE'}->{'DESCRIPTION'}->{'TITLE-INFO'}->{'COVER_DESC'};

  my $ImgID;

  if (exists $CoverIxists->{'src_path'} && $CoverIxists->{'src_path'} eq $ImgSrcFile ) {
    $ImgID = $CoverIxists->{'id'}; #уже отрабатывали картинку как cover, просто заменим src на готовый
  } else {

    unless (-f $ImgSrcFile) { #не нашли картинку
      $X->Msg("Can't find img".$ImgSrcFile." Replace to text [no image in epub file]\n","w");
      my $Doc = XML::LibXML::Document->new('1.0', 'utf-8');
      my $Text = $Doc->createTextNode('[no image in epub file]');
      return $Text;
   }

    unless (exists $ImgChecked{$ImgSrcFile}) {
      $X->_bs('img_info','Тип IMG');
      my $ImgInfo;
      my $ImgType;
      if ($ImgSrcFile =~ /.svg$/) {
        $ImgInfo = Image::ExifTool::ImageInfo($ImgSrcFile);
        $ImgType = ref $ImgInfo eq 'HASH' ? $ImgInfo->{'FileType'} : undef;
      } else {
        $ImgInfo = [Image::Size::imgsize($ImgSrcFile)];
        $ImgType = $ImgInfo->[2];
      }
      $X->_be('img_info');

      if ( !$ImgType || !$X->isAllowedImageType($ImgType) ) { #неизвестный формат
        $X->Msg("Can't detect img".$ImgSrcFile." Replace to text [bad img format]\n","w");
        my $Doc = XML::LibXML::Document->new('1.0', 'utf-8');
        my $Text = $Doc->createTextNode('[bad img format]');
        return $Text;
      }
    }
    $ImgChecked{$ImgSrcFile} = 1;

    $X->Msg("Find img, try transform: ".$Src."\n","w");

    my $ImgDestPath = $X->{'DestinationDir'}."/fb3/img";

    $Src =~ /.([^\/\.]+)$/;
    my $ImgType = $1;

    $ImgID = 'img_'.$X->UUID($ImgSrcFile);

    my $NewFileName = $ImgID.'.'.$ImgType;
    my $ImgDestFile = $ImgDestPath.'/'.$NewFileName;

    push @$ImgList, {
      'src_path' => $ImgSrcFile,
      'new_path' => "img/".$NewFileName, #заменим на новое имя
      'id' => $ImgID,
    } unless grep {$_->{id} eq $ImgID} @$ImgList;

    #Копируем исходник на новое место с новым уникальным именем
    unless (-f $ImgDestFile) {
      $X->Msg("copy $ImgSrcFile -> $ImgDestFile\n");
      $X->_bs('img_copy','Копирование IMG');
      FB3::Convert::copy($ImgSrcFile, $ImgDestFile) or $X->Error($!." [copy $ImgSrcFile -> $ImgDestFile]");        
      $X->_be('img_copy');
    }

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
  my ($Link, $Anchor) = split(/\#/, $Href, 2);

  my $NewHref =
  $Href ?
        $Href =~ /^[a-z]+\:/i
          ? $X->CorrectOuterLink($Href)
          : '#'.($Anchor ? 'link_' : '').$X->Path2ID( ($Link
                                                       ?$Href: #внешний section
                                                       basename($RelPath)."#".$Anchor #текущий section
                                                       ), $RelPath , 'process_href',
                                                        'skip' #не падать, если внешняя ссыль кривая
                                                      )
        : '';
  $NewHref = undef if $NewHref =~ /^\#$/ || $NewHref =~ /^\#link_$/; 

  if (defined($NewHref)) {
    $X->{'href_list'}->{$NewHref} = $Href if $X->trim($NewHref) ne '';
    $Node->setAttribute('xlink:href' => $NewHref);
  } else {
    $Node->parentNode->removeChild( $Node );
  }

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
    my $Excl = $X->{'allow_elements'}->{'p'}->{'exclude_if_inside'};
    if ( grep {$Child->nodeName eq $_} @$Excl ) {
      foreach my $ChildIns ($Child->getChildnodes) {
        $Wrap->addChild($ChildIns->cloneNode(1));
      }
    } else {
      $Wrap->addChild($Child->cloneNode(1));
    }
  }
 
  $NewNode->addChild($Wrap);

  return $NewNode;
}

sub FB3Creator {
	my $self = shift;
	my $X = shift;
  $X->Msg("Create FB3\n","w");

  my $Structure = shift || $X->{'STRUCTURE'} || $X->Error("Structure is empty");
  my $FB3Path = $X->{'DestinationDir'};

  #compile required files
  my $CoverSrc = $Structure->{'DESCRIPTION'}->{'TITLE-INFO'}->{'COVER_DESC'}->{'new_path'};

  $X->Msg("FB3: Create /_rels/.rels\n","w");
  my $FNrels="$FB3Path/_rels/.rels";
  open FHrels, ">$FNrels" or $X->Error("$FNrels: $!");
  print FHrels qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">}.
  ( $CoverSrc ? qq{
  <Relationship Id="rId0" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="fb3/$CoverSrc"/>} : '' ).qq{
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="fb3/meta/core.xml"/>
  <Relationship Id="rId2" Type="http://www.fictionbook.org/FictionBook3/relationships/Book" Target="fb3/description.xml"/>
  </Relationships>};
  close FHrels;

  $X->Msg("FB3: Create [Content_Types].xml\n","w");
  my $FNct="$FB3Path/[Content_Types].xml";
  open FHct, ">$FNct" or $X->Error("$FNct: $!");
  print FHct qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
   	<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
   	<Default Extension="png" ContentType="image/png"/>
   	<Default Extension="jpg" ContentType="image/jpeg"/>
    <Default Extension="jpeg" ContentType="image/jpeg"/>
   	<Default Extension="gif" ContentType="image/gif"/>
   	<Default Extension="svg" ContentType="image/svg+xml"/>
   	<Default Extension="xml" ContentType="application/xml"/>
   	<Default Extension="css" ContentType="text/css"/>
   	<Override PartName="/fb3/meta/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
   	<Override PartName="/fb3/description.xml" ContentType="application/fb3-description+xml"/>
   	<Override PartName="/fb3/body.xml" ContentType="application/fb3-body+xml"/>
  </Types>};
  close FHct;

  $X->Msg("FB3: Create /fb3/_rels/description.xml.rels\n","w");
  my $FNdrels="$FB3Path/fb3/_rels/description.xml.rels";
  open FHdrels, ">$FNdrels" or $X->Error("$FNdrels: $!");
  print FHdrels qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
   	<Relationship Id="rId0"
    		Target="body.xml"
    		Type="http://www.fictionbook.org/FictionBook3/relationships/body" />
  </Relationships>};
  close FHdrels;

 # !! Стили пока не трогаем !!
  #Скопируем стили
#  foreach my $css (@{$Structure->{'CSS_LIST'}}) {
#    my $SrcPath = $X->{'ContentDir'}."/".$css->{'src_path'};
#    my $CssDestPath = $X->{'DestinationDir'}."/fb3/style";
#    my $CssFile = $css->{'src_path'};
#    $CssFile =~ s/.*\/([^\/]+)/$1/g;
#    my $DstPath = $CssDestPath."/".$CssFile;
#    $X->Msg("copy $SrcPath -> $DstPath\n","w");
#    copy($SrcPath, $DstPath) or $X->Error($!);
#    $css->{'new_path'} = "style/".$CssFile;
#  }

  #ДО ЭТОГО МОМЕНТА МЫ МОЖЕМ ИЗМЕНЯТЬ $Structure, ТО ЕСТЬ ВМЕШИВАТЬСЯ В КОНЕЧНЫЙ РЕЗУЛЬТАТ ОТРИСОВКИ FB3
 # print Data::Dumper::Dumper($Structure);
 # exit;
  
  my $GlobalID  = $Structure->{'DESCRIPTION'}->{'DOCUMENT-INFO'}->{'ID'};
  my $TitleInfo = $Structure->{'DESCRIPTION'}->{'TITLE-INFO'};
  my $DocInfo   = $Structure->{'DESCRIPTION'}->{'DOCUMENT-INFO'};
  
  #Пишем body
  $X->Msg("FB3: Create /fb3/body.xml\n","w");
  my $FNbody="$FB3Path/fb3/body.xml";
  my $BodyAttr = {
  	'xmlns'=>"http://www.fictionbook.org/FictionBook3/body",
    'xmlns:xlink'=>"http://www.w3.org/1999/xlink",
    'id'=>$GlobalID,
  };

  $X->_bs('Obj2DOM_body','PAGES => DOM');
  my $Body = $X->Obj2DOM(
              obj=>{
                attributes=>{CP_compact=>1},
                value=>$Structure->{'PAGES'}->{'value'}
              },
              root=>{name=>'fb3-body', attributes=>$BodyAttr}
            );  
  $X->_be('Obj2DOM_body');
  
  #финальное приведение section к валидному виду
  foreach my $Section ($XC->findnodes( "/fb3-body/section/section", $Body), $XC->findnodes( "/fb3-body/section", $Body)) {
    $Section = $X->Transform2Valid(node=>$Section);
  }

  #финальное приведение table к валидному виду
  foreach my $Table ($XC->findnodes( "/fb3-body//table", $Body)) {
    $Table = $X->TransformTable2Valid(node=>$Table);
  }

  open FHbody, ">$FNbody" or $X->Error("$FNbody: $!");
  my $BodyString = $Body->toString(1);
  $BodyString =~ s/(<p>[^<>]*)<br\/>/$1<\/p><p>/g; #здесь уже правильный fb3, чистый и с параграфами, вот только <br/> нужно превратить в </p><p> 
  $BodyString =~ s/<br\/>/ /g;
  print FHbody $BodyString;
  close FHbody;

  #Пишем мету
  #Превращаем перл-структуру в DOM
  delete $Structure->{'PAGES'};
  $X->_bs('Obj2DOM_meta','META => DOM');
  my $Doc = $X->Obj2DOM(obj=>$Structure, like_parent=>0, compact=>0 ); 
  $X->_be('Obj2DOM_meta');

  #Пишем rels
  $X->Msg("FB3: Create /fb3/_rels/body.xml.rels\n","w");
  my $FNbodyrels="$FB3Path/fb3/_rels/body.xml.rels";
  open FHbodyrels, ">$FNbodyrels" or $X->Error("$FNbodyrels: $!");
  print FHbodyrels qq{<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.openxmlformats.org/package/2006/relationships" xmlns:xlink="http://www.w3.org/1999/xlink">
};
  foreach (@{$Structure->{'IMG_LIST'}}) {
    print FHbodyrels qq{  <Relationship Id="$_->{'id'}" Type="http://www.fictionbook.org/FictionBook3/relationships/image" Target="$_->{'new_path'}"/>
};
  }
  print FHbodyrels qq{</Relationships>};
  close FHbodyrels;
  
  #Пишем core
  $X->Msg("FB3: Create /fb3/meta/core.xml\n","w");
  my $FNcore="$FB3Path/fb3/meta/core.xml";
  open FHcore, ">$FNcore" or $X->Error("$FNcore: $!");
  print FHcore qq{<?xml version="1.0" encoding="UTF-8"?>
  <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns="http://www.fictionbook.org/FictionBook3/description" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/">
    <dc:title>}   . FB3::Convert::xmlescape($TitleInfo->{'BOOK-TITLE'}) . qq{</dc:title>
    <dc:subject>} . FB3::Convert::xmlescape($TitleInfo->{'ANNOTATION'}) . qq{</dc:subject>
    <dc:creator>};
  
  my $c=1;         
  foreach (@{$TitleInfo->{'AUTHORS'}}) {
    print FHcore FB3::Convert::xmlescape($_->{'first-name'}." ".$_->{'last-name'});
    print FHcore ", " if $c < scalar @{$TitleInfo->{'AUTHORS'}};
    $c++;
  }
  
  print FHcore qq{</dc:creator>
    <dc:description>}.FB3::Convert::xmlescape($TitleInfo->{'ANNOTATION'}).qq{</dc:description>
    <cp:keywords>XML, FictionBook, eBook, OPC</cp:keywords>
    <cp:revision>1.00</cp:revision>
    }.
  ($DocInfo->{'DATE'}->{'attributes'}->{'value'}?qq{<dcterms:created xsi:type="dcterms:W3CDTF">}.$DocInfo->{'DATE'}->{'attributes'}->{'value'}.qq{</dcterms:created>
    }:'')
  .qq{<cp:contentStatus>Draft</cp:contentStatus>
    <cp:category>};
  
  $c=1;         
  foreach (@{$TitleInfo->{'GENRES'}}) {
    print FHcore FB3::Convert::xmlescape($_);
    print FHcore ", " if $c < scalar @{$TitleInfo->{'GENRES'}};
    $c++;
  }

  print FHcore qq{</cp:category>
  </cp:coreProperties>};
  close FHcore;
  #Пишем description
  $X->Msg("FB3: Create /fb3/description.xml\n","w");
  my $FNdesc="$FB3Path/fb3/description.xml";
  open FHdesc, ">$FNdesc" or $X->Error("$FNdesc: $!");
  print FHdesc qq{<?xml version="1.0" encoding="UTF-8"?>
<fb3-description xmlns="http://www.fictionbook.org/FictionBook3/description" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xlink="http://www.w3.org/1999/xlink" id="}.FB3::Convert::xmlescape($GlobalID).qq{" version="1.0">
  };

  print FHdesc qq{<title>
    <main>} . FB3::Convert::xmlescape($TitleInfo->{'BOOK-TITLE'}) . qq{</main>
  </title>
  };
    
  print FHdesc qq{<fb3-relations>
    };

  foreach (@{$TitleInfo->{'AUTHORS'}}) {

    my $First  = FB3::Convert::xmlescape($_->{'first-name'} );
    my $Middle = FB3::Convert::xmlescape($_->{'middle-name'});
    my $Last   = FB3::Convert::xmlescape($_->{'last-name'}  ) || "Unknown";
    my $Link   = FB3::Convert::xmlescape($_->{'link'}) || "author";

    print FHdesc qq{<subject link="$Link" id="}.($_->{'id'}||'00000000-0000-0000-0000-000000000000').qq{">
      <title>
        <main>
          }.
      ($First?$First.' '.$Last:$Last).qq{
        </main>
      </title>}
      .($First?qq{
      <first-name>}.$First.'</first-name>':'')
      .($Middle?qq{
      <middle-name>}.$Middle.qq{</middle-name>}:'')
      .qq{
      <last-name>}.$Last.qq{</last-name>
    </subject>
  };
  }

  print FHdesc qq{</fb3-relations>
  };

  print FHdesc qq{<fb3-classification>
    };
  foreach (@{$TitleInfo->{'GENRES'}}) {
    print FHdesc qq{<subject>} . ( exists $GenreTranslate{$_} ? $GenreTranslate{$_} : FB3::Convert::xmlescape($_) ) . qq{</subject>
    };
  }
  print FHdesc qq{</fb3-classification>
  };
  
  print FHdesc qq{<lang>}.$DocInfo->{'LANGUAGE'}.qq{</lang>
  <written>
    <lang>} . FB3::Convert::xmlescape($DocInfo->{'LANGUAGE'}) . qq{</lang>
  </written>
  };

  my $DCDate = $DocInfo->{'DATE'}->{'attributes'}->{'value'}."T".$DocInfo->{'TIME'}->{'attributes'}->{'value'};
  print FHdesc qq{<document-info created="}.$DCDate.qq{" updated="}.$DCDate.qq{"/>
};

  print FHdesc qq{  <annotation>
    <p>} . FB3::Convert::xmlescape($TitleInfo->{'ANNOTATION'}) . qq{</p>
  </annotation>
} if $TitleInfo->{'ANNOTATION'};

  print FHdesc qq{</fb3-description>};
  close FHdesc;
 
  return $FB3Path;
}

1;
