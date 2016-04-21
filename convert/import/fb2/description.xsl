<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0"
  xmlns="http://www.fictionbook.org/FictionBook3/description"
  exclude-result-prefixes="fb">
  
  <xsl:include href="general.xsl"/>
  
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  
  <xsl:variable name="description" select="/fb:FictionBook/fb:description"/>
  <xsl:variable name="title-info" select="$description/fb:title-info"/>
  
  <xsl:variable name="globalID">
    <xsl:value-of select="$description/fb:document-info/fb:id"/>
  </xsl:variable>
  
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="/">
    <fb3-description id="{$globalID}"  version="1.0">
      <xsl:call-template name="title"/>
      <!-- there are no ids in FB2 sequences, but FB3 require them. Because there is no
      way to discover ids - completely ignore this sequences block -->
      <!--<xsl:call-template name="sequence"/>-->
      <xsl:call-template name="relations"/>
      <xsl:call-template name="classification"/>
      <xsl:call-template name="lang"/>
      <xsl:call-template name="written"/>
      <xsl:call-template name="document-info"/>
      <xsl:call-template name="paper-publish-info"/>
      <xsl:call-template name="annotation"/>
    </fb3-description>
  </xsl:template>
  
  <xsl:template name="title">
    <title>
      <main><xsl:value-of select="$title-info/fb:book-title"/></main>
    </title>
  </xsl:template>
  
  <xsl:template name="relations">
    <fb3-relations>
      <xsl:for-each select="$title-info/fb:author
          | $title-info/fb:translator">

        <subject>
          <xsl:attribute name="link">
            <xsl:value-of select="local-name()"/>
          </xsl:attribute>
          <xsl:attribute name="id">
            <xsl:choose>
              <xsl:when test="fb:id"><xsl:value-of select="fb:id"/></xsl:when>
              <xsl:otherwise>00000000-0000-0000-0000-000000000000</xsl:otherwise>
            </xsl:choose>
          </xsl:attribute>
          <xsl:variable name="first" select="fb:first-name/text()" />
          <xsl:variable name="middle" select="fb:middle-name/text()" />
          <xsl:variable name="last">
            <xsl:choose>
              <xsl:when test="fb:last-name/text()">
                <xsl:value-of select="fb:last-name/text()"/>
              </xsl:when>
              <xsl:otherwise>Unknown</xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <title>
            <main>
              <xsl:choose>
                <xsl:when test="$first">
                  <xsl:value-of select="concat($first, ' ', $last)"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:value-of select="$last"/>
                </xsl:otherwise>
              </xsl:choose>
            </main>
          </title>
          <xsl:if test="$first">
            <first-name><xsl:value-of select="$first"/></first-name>
          </xsl:if>
          <xsl:if test="$middle">
            <middle-name><xsl:value-of select="$middle"/></middle-name>
          </xsl:if>
          <last-name><xsl:value-of select="$last"/></last-name>
        </subject>
      </xsl:for-each>
    </fb3-relations>
  </xsl:template>
  
  <xsl:key name="genre" match="/fb:FictionBook/fb:description/fb:title-info/fb:genre/text()" use="."/>

  <xsl:template name="classification">
    <fb3-classification>
      <!-- выбираем уникальные записи в жанрах -->
      <xsl:for-each
        select="$title-info/fb:genre/text()[generate-id() = generate-id(key('genre',.)[1])]" >

        <subject>
          <xsl:choose>
            <xsl:when test=".='accounting'">Бухучет, налогообложение, аудит</xsl:when>
            <xsl:when test=".='adventure'">Приключения</xsl:when>
            <xsl:when test=".='adv_animal'">Природа и животные</xsl:when>
            <xsl:when test=".='adv_geo'">Книги о Путешествиях</xsl:when>
            <xsl:when test=".='adv_history'">Исторические приключения</xsl:when>
            <xsl:when test=".='adv_maritime'">Морские приключения</xsl:when>
            <xsl:when test=".='adv_western'">Вестерны</xsl:when>
            <xsl:when test=".='antique'">Старинная литература</xsl:when>
            <xsl:when test=".='antique_ant'">Античная литература</xsl:when>
            <xsl:when test=".='antique_east'">Древневосточная литература</xsl:when>
            <xsl:when test=".='antique_european'">Европейская старинная литература</xsl:when>
            <xsl:when test=".='antique_myths'">Мифы. Легенды. Эпос</xsl:when>
            <xsl:when test=".='antique_russian'">Древнерусская литература</xsl:when>
            <xsl:when test=".='aphorism_quote'">Афоризмы и цитаты</xsl:when>
            <xsl:when test=".='architecture_book'">Архитектура</xsl:when>
            <xsl:when test=".='auto_regulations'">Автомобили и ПДД</xsl:when>
            <xsl:when test=".='banking'">Банковское дело</xsl:when>
            <xsl:when test=".='beginning_authors'">Начинающие авторы</xsl:when>
            <xsl:when test=".='children'">Книги для детей</xsl:when>
            <xsl:when test=".='child_adv'">Детские приключения</xsl:when>
            <xsl:when test=".='child_det'">Детские детективы</xsl:when>
            <xsl:when test=".='child_education'">Учебная литература</xsl:when>
            <xsl:when test=".='child_prose'">Детская проза</xsl:when>
            <xsl:when test=".='child_sf'">Детская фантастика</xsl:when>
            <xsl:when test=".='child_tale'">Сказки</xsl:when>
            <xsl:when test=".='child_verse'">Детские стихи</xsl:when>
            <xsl:when test=".='cinema_theatre'">Кинематограф, театр</xsl:when>
            <xsl:when test=".='city_fantasy'">Городское фэнтези</xsl:when>
            <xsl:when test=".='computers'">Компьютеры</xsl:when>
            <xsl:when test=".='comp_db'">Базы данных</xsl:when>
            <xsl:when test=".='comp_hard'">Компьютерное Железо</xsl:when>
            <xsl:when test=".='comp_osnet'">ОС и Сети</xsl:when>
            <xsl:when test=".='comp_programming'">Программирование</xsl:when>
            <xsl:when test=".='comp_soft'">Программы</xsl:when>
            <xsl:when test=".='comp_www'">Интернет</xsl:when>
            <xsl:when test=".='detective'">Современные детективы</xsl:when>
            <xsl:when test=".='det_action'">Боевики</xsl:when>
            <xsl:when test=".='det_classic'">Классические детективы</xsl:when>
            <xsl:when test=".='det_crime'">Криминальные боевики</xsl:when>
            <xsl:when test=".='det_espionage'">Шпионские детективы</xsl:when>
            <xsl:when test=".='det_hard'">Крутой детектив</xsl:when>
            <xsl:when test=".='det_history'">Исторические детективы</xsl:when>
            <xsl:when test=".='det_irony'">Иронические детективы</xsl:when>
            <xsl:when test=".='det_police'">Полицейские детективы</xsl:when>
            <xsl:when test=".='det_political'">Политические детективы</xsl:when>
            <xsl:when test=".='dragon_fantasy'">Фэнтези про драконов</xsl:when>
            <xsl:when test=".='dramaturgy'">Драматургия</xsl:when>
            <xsl:when test=".='economics'">Экономика</xsl:when>
            <xsl:when test=".='essays'">Эссе</xsl:when>
            <xsl:when test=".='fantasy_fight'">Боевое фэнтези</xsl:when>
            <xsl:when test=".='foreign_action'">Зарубежные боевики</xsl:when>
            <xsl:when test=".='foreign_adventure'">Зарубежные приключения</xsl:when>
            <xsl:when test=".='foreign_antique'">Зарубежная старинная литература</xsl:when>
            <xsl:when test=".='foreign_business'">Зарубежная деловая литература</xsl:when>
            <xsl:when test=".='foreign_children'">Зарубежные детские книги</xsl:when>
            <xsl:when test=".='foreign_comp'">Зарубежная компьютерная литература</xsl:when>
            <xsl:when test=".='foreign_contemporary'">Современная зарубежная литература</xsl:when>
            <xsl:when test=".='foreign_desc'">Зарубежная справочная литература</xsl:when>
            <xsl:when test=".='foreign_detective'">Зарубежные детективы</xsl:when>
            <xsl:when test=".='foreign_dramaturgy'">Зарубежная драматургия</xsl:when>
            <xsl:when test=".='foreign_edu'">Зарубежная образовательная литература</xsl:when>
            <xsl:when test=".='foreign_fantasy'">Зарубежное фэнтези</xsl:when>
            <xsl:when test=".='foreign_home'">Зарубежная прикладная и научно-популярная литература</xsl:when>
            <xsl:when test=".='foreign_humor'">Зарубежный юмор</xsl:when>
            <xsl:when test=".='foreign_language'">Иностранные языки</xsl:when>
            <xsl:when test=".='foreign_love'">Зарубежные любовные романы</xsl:when>
            <xsl:when test=".='foreign_other'">Зарубежное</xsl:when>
            <xsl:when test=".='foreign_poetry'">Зарубежные стихи</xsl:when>
            <xsl:when test=".='foreign_prose'">Зарубежная классика</xsl:when>
            <xsl:when test=".='foreign_psychology'">Зарубежная психология</xsl:when>
            <xsl:when test=".='foreign_publicism'">Зарубежная публицистика</xsl:when>
            <xsl:when test=".='foreign_religion'">Зарубежная эзотерическая и религиозная литература</xsl:when>
            <xsl:when test=".='foreign_sf'">Зарубежная фантастика</xsl:when>
            <xsl:when test=".='geography_book'">География</xsl:when>
            <xsl:when test=".='geo_guides'">Путеводители</xsl:when>
            <xsl:when test=".='global_economy'">ВЭД</xsl:when>
            <xsl:when test=".='historical_fantasy'">Историческое фэнтези</xsl:when>
            <xsl:when test=".='home'">Дом и Семья</xsl:when>
            <xsl:when test=".='home_cooking'">Кулинария</xsl:when>
            <xsl:when test=".='home_crafts'">Хобби, Ремесла</xsl:when>
            <xsl:when test=".='home_diy'">Сделай Сам</xsl:when>
            <xsl:when test=".='home_entertain'">Развлечения</xsl:when>
            <xsl:when test=".='home_garden'">Сад и Огород</xsl:when>
            <xsl:when test=".='home_health'">Здоровье</xsl:when>
            <xsl:when test=".='home_pets'">Домашние Животные</xsl:when>
            <xsl:when test=".='home_sex'">Эротика, Секс</xsl:when>
            <xsl:when test=".='home_sport'">Спорт, фитнес</xsl:when>
            <xsl:when test=".='humor'">Юмор</xsl:when>
            <xsl:when test=".='humor_anecdote'">Анекдоты</xsl:when>
            <xsl:when test=".='humor_fantasy'">Юмористическое фэнтези</xsl:when>
            <xsl:when test=".='humor_prose'">Юмористическая проза</xsl:when>
            <xsl:when test=".='humor_verse'">Юмористические стихи</xsl:when>
            <xsl:when test=".='industries'">Отраслевые издания</xsl:when>
            <xsl:when test=".='job_hunting'">Поиск работы, карьера</xsl:when>
            <xsl:when test=".='literature_18'">Литература 18 века</xsl:when>
            <xsl:when test=".='literature_19'">Литература 19 века</xsl:when>
            <xsl:when test=".='literature_20'">Литература 20 века</xsl:when>
            <xsl:when test=".='love_contemporary'">Современные любовные романы</xsl:when>
            <xsl:when test=".='love_detective'">Остросюжетные любовные романы</xsl:when>
            <xsl:when test=".='love_erotica'">Эротическая литература</xsl:when>
            <xsl:when test=".='love_fantasy'">Любовное фэнтези</xsl:when>
            <xsl:when test=".='love_history'">Исторические любовные романы</xsl:when>
            <xsl:when test=".='love_sf'">Любовно-фантастические романы</xsl:when>
            <xsl:when test=".='love_short'">Короткие любовные романы</xsl:when>
            <xsl:when test=".='magician_book'">Книги про волшебников</xsl:when>
            <xsl:when test=".='management'">Управление, подбор персонала</xsl:when>
            <xsl:when test=".='marketing'">Маркетинг, PR, реклама</xsl:when>
            <xsl:when test=".='military_special'">Военное дело, спецслужбы</xsl:when>
            <xsl:when test=".='music_dancing'">Музыка, балет</xsl:when>
            <xsl:when test=".='narrative'">Повести</xsl:when>
            <xsl:when test=".='newspapers'">Газеты</xsl:when>
            <xsl:when test=".='nonfiction'">Документальная литература</xsl:when>
            <xsl:when test=".='nonf_biography'">Биографии и Мемуары</xsl:when>
            <xsl:when test=".='nonf_criticism'">Критика</xsl:when>
            <xsl:when test=".='nonf_publicism'">Публицистика</xsl:when>
            <xsl:when test=".='org_behavior'">Корпоративная культура</xsl:when>
            <xsl:when test=".='paper_work'">Делопроизводство</xsl:when>
            <xsl:when test=".='pedagogy_book'">Педагогика</xsl:when>
            <xsl:when test=".='periodic'">Журналы</xsl:when>
            <xsl:when test=".='personal_finance'">Личные финансы</xsl:when>
            <xsl:when test=".='poetry'">Поэзия</xsl:when>
            <xsl:when test=".='popadanec'">Попаданцы</xsl:when>
            <xsl:when test=".='popular_business'">О бизнесе популярно</xsl:when>
            <xsl:when test=".='prose_classic'">Классическая проза</xsl:when>
            <xsl:when test=".='prose_counter'">Контркультура</xsl:when>
            <xsl:when test=".='prose_history'">Историческая литература</xsl:when>
            <xsl:when test=".='prose_military'">Книги о войне</xsl:when>
            <xsl:when test=".='prose_rus_classic'">Русская классика</xsl:when>
            <xsl:when test=".='prose_su_classics'">Советская литература</xsl:when>
            <xsl:when test=".='psy_alassic'">Классики психологии</xsl:when>
            <xsl:when test=".='psy_childs'">Детская психология</xsl:when>
            <xsl:when test=".='psy_generic'">Общая психология</xsl:when>
            <xsl:when test=".='psy_personal'">Личностный рост</xsl:when>
            <xsl:when test=".='psy_sex_and_family'">Секс и семейная психология</xsl:when>
            <xsl:when test=".='psy_social'">Социальная психология</xsl:when>
            <xsl:when test=".='psy_theraphy'">Психотерапия и консультирование</xsl:when>
            <xsl:when test=".='real_estate'">Недвижимость</xsl:when>
            <xsl:when test=".='reference'">Справочная литература</xsl:when>
            <xsl:when test=".='ref_dict'">Словари</xsl:when>
            <xsl:when test=".='ref_encyc'">Энциклопедии</xsl:when>
            <xsl:when test=".='ref_guide'">Руководства</xsl:when>
            <xsl:when test=".='ref_ref'">Справочники</xsl:when>
            <xsl:when test=".='religion'">Религия</xsl:when>
            <xsl:when test=".='religion_esoterics'">Эзотерика</xsl:when>
            <xsl:when test=".='religion_rel'">Религиозные тексты</xsl:when>
            <xsl:when test=".='religion_self'">Самосовершенствование</xsl:when>
            <xsl:when test=".='russian_contemporary'">Современная русская литература</xsl:when>
            <xsl:when test=".='russian_fantasy'">Русское фэнтези</xsl:when>
            <xsl:when test=".='science'">Прочая образовательная литература</xsl:when>
            <xsl:when test=".='sci_biology'">Биология</xsl:when>
            <xsl:when test=".='sci_chem'">Химия</xsl:when>
            <xsl:when test=".='sci_culture'">Культурология</xsl:when>
            <xsl:when test=".='sci_history'">История</xsl:when>
            <xsl:when test=".='sci_juris'">Юриспруденция, право</xsl:when>
            <xsl:when test=".='sci_linguistic'">Языкознание</xsl:when>
            <xsl:when test=".='sci_math'">Математика</xsl:when>
            <xsl:when test=".='sci_medicine'">Медицина</xsl:when>
            <xsl:when test=".='sci_philosophy'">Философия</xsl:when>
            <xsl:when test=".='sci_phys'">Физика</xsl:when>
            <xsl:when test=".='sci_politics'">Политика, политология</xsl:when>
            <xsl:when test=".='sci_religion'">Религиоведение</xsl:when>
            <xsl:when test=".='sci_tech'">Техническая литература</xsl:when>
            <xsl:when test=".='sf'">Научная фантастика</xsl:when>
            <xsl:when test=".='sf_action'">Боевая фантастика</xsl:when>
            <xsl:when test=".='sf_cyberpunk'">Киберпанк</xsl:when>
            <xsl:when test=".='sf_detective'">Детективная фантастика</xsl:when>
            <xsl:when test=".='sf_heroic'">Героическая фантастика</xsl:when>
            <xsl:when test=".='sf_history'">Историческая фантастика</xsl:when>
            <xsl:when test=".='sf_horror'">Ужасы и Мистика</xsl:when>
            <xsl:when test=".='sf_humor'">Юмористическая фантастика</xsl:when>
            <xsl:when test=".='sf_social'">Социальная фантастика</xsl:when>
            <xsl:when test=".='sf_space'">Космическая фантастика</xsl:when>
            <xsl:when test=".='short_story'">Рассказы</xsl:when>
            <xsl:when test=".='sketch'">Очерки</xsl:when>
            <xsl:when test=".='small_business'">Малый бизнес</xsl:when>
            <xsl:when test=".='sociology_book'">Социология</xsl:when>
            <xsl:when test=".='stock'">Ценные бумаги, инвестиции</xsl:when>
            <xsl:when test=".='thriller'">Триллеры</xsl:when>
            <xsl:when test=".='upbringing_book'">Воспитание детей</xsl:when>
            <xsl:when test=".='vampire_book'">Книги про вампиров</xsl:when>
            <xsl:when test=".='visual_arts'">Изобразительное искусство, фотография</xsl:when>
            <xsl:otherwise>Жанр не определен</xsl:otherwise>
          </xsl:choose>
        </subject>
      </xsl:for-each>
      <!--
      <target-audience age-min="9" age-max="99" education="high">
        Для широкого круга читателей
      </target-audience>
      <setting country="" place="" date="" date-from="" date-to="" age=""/>
      <udk/>
      <bbk/>
      -->
    </fb3-classification>
  </xsl:template>
  
  <xsl:template name="lang">
    <xsl:variable name="lang" select="$title-info/fb:lang"/>
    <lang><xsl:value-of select="$lang"/></lang>
  </xsl:template>
  
  <xsl:template name="written">
    <written>
      <lang>
        <xsl:choose>
          <xsl:when test="$title-info/fb:src-lang">
            <xsl:value-of select="$title-info/fb:src-lang"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:value-of select="$title-info/fb:lang"/>
          </xsl:otherwise>
        </xsl:choose>
      </lang>
      <xsl:variable name="date" select="$title-info/fb:date"/>
      <xsl:if test="$date">
        <date>
          <xsl:if test="$date/@value">
            <xsl:attribute name="value">
              <xsl:value-of select="$date/@value"/>
            </xsl:attribute>
          </xsl:if>
          <xsl:value-of select="$date" />
        </date>
      </xsl:if>
    </written>
  </xsl:template>
  
  <xsl:template name="document-info">
    <xsl:variable name="docinfo" select="$description/fb:document-info"/>
    <document-info>
      <xsl:variable name="created">
        <xsl:choose>
          <xsl:when test="$docinfo/fb:date/@value">
            <xsl:value-of select="concat( $docinfo/fb:date/@value, 'T00:00:00' )"/>
          </xsl:when>
          <!-- No proper data in FB2 - inserting a dummy date (schema valid
            garbage in, schema valid garbage out) -->
          <xsl:otherwise>1970-01-01T00:00:00</xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:attribute name="created">
        <xsl:call-template name="date-format">
          <xsl:with-param name="date" select="$created"/>
        </xsl:call-template>
      </xsl:attribute>
      <xsl:attribute name="updated">
        <xsl:call-template name="date-format">
          <xsl:with-param name="date" select="$created"/>
        </xsl:call-template>
      </xsl:attribute>
      <xsl:if test="$docinfo/fb:src-url">
        <xsl:attribute name="src-url">
          <xsl:value-of select="$docinfo/fb:src-url"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:if test="$docinfo/fb:src-ocr">
        <xsl:attribute name="ocr">
          <xsl:value-of select="$docinfo/fb:src-ocr"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:variable name="author" select="$docinfo/fb:author"/>
      <xsl:variable name="editor-name" select="normalize-space(concat(
        $author/fb:first-name, ' ', $author/fb:last-name))"/>
      <xsl:variable name="editor">
        <xsl:choose>
          <xsl:when test="$editor-name and $author/fb:nickname">
            <xsl:value-of select="concat($editor-name, ' a.k.a. ', $author/fb:nickname)"/>
          </xsl:when>
          <xsl:when test="$editor-name">
            <xsl:value-of select="$editor-name"/>
          </xsl:when>
          <xsl:when test="$author/fb:nickname">
            <xsl:value-of select="$author/fb:nickname"/>
          </xsl:when>
        </xsl:choose>
      </xsl:variable>
      <xsl:if test="$editor">
        <xsl:attribute name="editor">
          <xsl:value-of select="$editor"/>
        </xsl:attribute>
      </xsl:if>
    </document-info>
  </xsl:template>
  
  <xsl:template name="paper-publish-info">
    <xsl:variable name="pubinfo" select="$description/fb:publish-info"/>
    <xsl:if test="$pubinfo/fb:book-name">
      <paper-publish-info>
        <xsl:if test="$pubinfo/fb:book-name">
          <xsl:attribute name="title">
            <xsl:value-of select="$pubinfo/fb:book-name"/>
          </xsl:attribute>
        </xsl:if>
        <xsl:if test="$pubinfo/fb:publisher">
          <xsl:attribute name="publisher">
            <xsl:value-of select="$pubinfo/fb:publisher"/>
          </xsl:attribute>
        </xsl:if>
        <xsl:if test="$pubinfo/fb:city">
          <xsl:attribute name="city">
            <xsl:value-of select="$pubinfo/fb:city"/>
          </xsl:attribute>
        </xsl:if>
        <xsl:if test="$pubinfo/fb:year">
          <xsl:attribute name="year">
            <xsl:value-of select="$pubinfo/fb:year"/>
          </xsl:attribute>
        </xsl:if>
        <xsl:for-each select="$pubinfo/fb:isbn">
          <isbn><xsl:value-of select="text()"/></isbn>
        </xsl:for-each>
        <!-- in FB2 publish-info block there was tree structure of sequences, but
        in FB3 we have only a list (tree structure is in document-info/sequence ) -->
        <xsl:for-each select="$pubinfo//fb:sequence">
          <sequence><xsl:value-of select="@name"/></sequence>
        </xsl:for-each>
      </paper-publish-info>
    </xsl:if>
  </xsl:template>
  
  <xsl:template name="annotation">
    <!-- print annotation if it exists and has at least one nested non-empty <p>
    element -->
    <xsl:variable name="first-p"
      select="$title-info/fb:annotation/fb:p[text()][1]"/>
    <xsl:if test="$first-p">
      <annotation>
        <xsl:apply-templates select="$first-p | $first-p/following-sibling::*
          [ local-name() = 'p' or local-name() = 'empty-line' ]"/>
      </annotation>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="fb:p">
    <p><xsl:apply-templates/></p>
  </xsl:template>
  
  <xsl:template match="fb:empty-line">
    <br/>
  </xsl:template>
  
  <xsl:template match="fb:strong">
    <strong><xsl:apply-templates/></strong>
  </xsl:template>
  
  <xsl:template match="fb:emphasis">
    <em><xsl:apply-templates/></em>
  </xsl:template>

  <xsl:template match="fb:strikethrough|fb:sub|fb:sup|fb:code|fb:style">
    <xsl:apply-templates/>
  </xsl:template>
  
  <xsl:template match="fb:a">
    <xsl:choose>
      <xsl:when test="@type='note'">
        <xsl:call-template name="note">
          <xsl:with-param name="item" select="."/>
        </xsl:call-template>
      </xsl:when>
    </xsl:choose>
  </xsl:template>
  
</xsl:stylesheet>
