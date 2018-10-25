<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE XSL [
	<!ENTITY is_notebody "ancestor::fb:body[1]/@name='notes' and @id">
]>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0"
  xmlns="http://www.fictionbook.org/FictionBook3/body"
  exclude-result-prefixes="fb">
  
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  
  <xsl:variable name="description" select="/fb:FictionBook/fb:description"/>
  
  <xsl:variable name="globalID">
    <xsl:value-of select="$description/fb:document-info/fb:id"/>
  </xsl:variable>
  
  <xsl:variable name="preID" select="substring-before($globalID, '-')"/>
  <xsl:variable name="posID" select="substring-after(substring-after($globalID, '-'), '-')"/>
  
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="/">
    <xsl:apply-templates/>
  </xsl:template>
  
  <xsl:template match="fb:FictionBook">
    <fb3-body id="{$globalID}">
      <xsl:apply-templates/>
    </fb3-body>
  </xsl:template>
  
  <xsl:template match="/fb:FictionBook/fb:description"/>
  
  <xsl:template match="fb:body[not(@name='notes')]">
      <xsl:apply-templates select="fb:title"/>
      <xsl:apply-templates select="fb:epigraph"/>
      <xsl:apply-templates select="fb:section"/>
  </xsl:template>

<!--      пропускаем секции, состоящие из одних пустых строк-->
	<xsl:template match="fb:section[count(fb:empty-line)=count(fb:*)]"/>

  <xsl:template match="fb:section[not(count(fb:empty-line)=count(fb:*))]">
    <xsl:choose>
<!--      основная секция сносок - без id-->
      <xsl:when test="parent::fb:body/@name='notes' and not(@id)">
        <xsl:apply-templates select="fb:section"/>
      </xsl:when>
<!--      сноски с id внутри блока сносок-->
      <xsl:when test="&is_notebody;">
        <notebody id="{@id}">
          <xsl:apply-templates/>
        </notebody>
      </xsl:when>
<!--      sections inside notes (this happens sometimes) -->
      <xsl:when test="parent::fb:section[&is_notebody;]">
        <xsl:apply-templates/>
      </xsl:when>
      <xsl:otherwise>
<!--        обычная секция в тексте-->
        <section>
          <xsl:attribute name="id">
            <xsl:apply-templates select="." mode="subsectionID"/>
          </xsl:attribute>
          <xsl:apply-templates select="fb:title"/>
          <xsl:apply-templates select="fb:epigraph"/>
          <!-- there're no section covers in fb3
          <xsl:apply-templates select="fb:image[following-sibling::fb:section"/>
          -->
          <xsl:apply-templates select="fb:annotation"/>
          <xsl:apply-templates select="fb:section"/>
          <xsl:apply-templates select="fb:p | fb:poem | fb:subtitle |
            fb:cite | fb:empty-line | fb:table | fb:div |
            fb:image[not(following-sibling::fb:section)]"/>
        </section>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="fb:title">
    <!-- title in FB3 must start with p-element -->
    <xsl:if test="fb:p[1]">
      <title>
				<xsl:if test="parent::fb:body[not(@name='notes')] and preceding-sibling::*[1][local-name()='image']">
					<p>
						<xsl:call-template name="title-image"/>
					</p>
				</xsl:if>
        <xsl:apply-templates select="fb:p[1] | fb:p[1]/following-sibling::*"/>
      </title>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="fb:subtitle">
    <!-- In FB2 element subtitle appears inside many types of nodes. In FB3 it
    appears only inside sections -->
    <xsl:choose>
      <xsl:when test="parent::fb:section[not(&is_notebody;)]">
        <subtitle><xsl:apply-templates/></subtitle>
      </xsl:when>
      <xsl:otherwise>
        <xsl:choose>
          <xsl:when test="not(preceding-sibling::*) and (following-sibling::*) and not(parent::fb:cite[parent::fb:section[ancestor::fb:body[@name='notes']]]/preceding-sibling::*) and not(following-sibling::fb:subtitle)">
            <title>
              <p><xsl:apply-templates/></p>
            </title>
          </xsl:when>
          <xsl:otherwise>
              <xsl:call-template name='AddStrong'/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="AddStrong">
    <xsl:choose>
      <xsl:when test="fb:strong">
        <p><xsl:apply-templates/></p>
      </xsl:when>
      <xsl:otherwise>
        <p><strong><xsl:apply-templates/></strong></p>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="fb:epigraph">
    <xsl:for-each select="*">
      <xsl:choose>
        <!-- convert each cite to separate epigraph -->
        <xsl:when test="local-name()='cite'">
          <xsl:call-template name="PHolderType">
            <xsl:with-param name="holder-name">epigraph</xsl:with-param>
          </xsl:call-template>
        </xsl:when>
        <!-- all the other elements except the cites are placed together inside
        one epigraph --> 
        <xsl:when test="not(preceding-sibling::*)
            or preceding-sibling::*[1][local-name()='cite']">

          <xsl:choose>
            <xsl:when test="following-sibling::fb:cite">

              <xsl:variable name="before-cite"
                select="following-sibling::fb:cite/preceding-sibling::*"/>

              <xsl:call-template name="put-in-epigraph">
                <!-- intersection of $before-cite and following-sibling::* -->
                <xsl:with-param name="elements"
                  select=". | following-sibling::*
                    [ count(.|$before-cite) = count($before-cite) ]"/>
              </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
              <xsl:call-template name="put-in-epigraph">
                <xsl:with-param name="elements"
                  select=".|following-sibling::*"/>
              </xsl:call-template>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:when>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="put-in-epigraph">
    <xsl:param name="elements"/>

    <!-- according to scheme first element must be p or poem. Throw away all others -->
    <xsl:variable name="first-valid" select="$elements
      [ local-name()='p' or local-name()='poem' ][1]"/>
    <xsl:if test="$first-valid">
      <!-- intersection of $first-valid/following-sibling::* and $elements -->
      <epigraph>
        <xsl:apply-templates select="$first-valid
          | $first-valid/following-sibling::*[ count(.|$elements) = count($elements) ]"/>
      </epigraph>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="fb:annotation">
    <annotation><xsl:apply-templates/></annotation>
  </xsl:template>

  <xsl:template match="fb:blockquote">
    <blockquote><xsl:apply-templates/></blockquote>
  </xsl:template>

  <!-- cite/text-author превращаем либо просто в subscription, либо просто в blockquote -->
  <xsl:template match="fb:cite[fb:text-author and count(fb:text-author) = count(*)]">
    <xsl:choose>
      <xsl:when test="parent::fb:section">
        <blockquote>
          <xsl:apply-templates select="fb:text-author" mode="grouped"/>
        </blockquote>
      </xsl:when>
      <xsl:otherwise>
        <xsl:apply-templates/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="fb:cite">
    <!--
    * fb3 analogue for "cite" is "blockquote"
    * blockquote has simpler markup than cite
    * we can honestly convert cites with simple content to blockquote
    * we have to convert cites with more complex content to divs
    -->
    <xsl:choose>
			<xsl:when test="parent::fb:section[ancestor::fb:body[@name='notes']]">
				<xsl:apply-templates/>
			</xsl:when>
      <xsl:when test="fb:poem | fb:table">
        <div width="80%"><xsl:apply-templates/></div>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="PHolderType">
          <xsl:with-param name="holder-name">blockquote</xsl:with-param>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="PHolderType">
    <xsl:param name="holder-name"/>
    <xsl:param name="paragraph-name">p</xsl:param>

    <!-- must start with p element. subtitle will be converted to paragraph later-->
    <xsl:variable name="first-p" select="fb:*[local-name()=$paragraph-name][1] | fb:subtitle[1]"/>
    <xsl:if test="$first-p">
      <xsl:element name="{$holder-name}">
        <xsl:call-template name="TitledType"/>
        <xsl:apply-templates select="$first-p | $first-p/following-sibling::*
          [ local-name()=$paragraph-name or local-name()='empty-line' ] | fb:subtitle"/>
				<xsl:apply-templates select="fb:text-author"/>
      </xsl:element>
    </xsl:if>
  </xsl:template>

  <xsl:template name="TitledType">
    <xsl:apply-templates select="fb:title"/>
    <xsl:apply-templates select="fb:epigraph"/>
  </xsl:template>
  
  <!-- 
    <text-author>FOO</text-author>
    <text-author>BAR</text-author>
  convert to
    <subscription>
      <p>FOO</p>
      <p>BAR</p>
    </subscription>
  1) select each first text-author element in group of these elements with template+match
  2) find all following text-author elements and place them as in example above
  -->
  <xsl:template match="fb:text-author[ not(parent::fb:cite[parent::fb:section[ancestor::fb:body[@name='notes']]]) and (not(preceding-sibling::*) or preceding-sibling::*[1][not(local-name()='text-author')]) ]">

    <xsl:variable name="first_non_text_author"
      select="following-sibling::*[local-name()!='text-author'][1]"/>

    <subscription>
      <xsl:choose>
        <xsl:when test="$first_non_text_author">
          <!-- последующие text-author узлы находим как пересечение групп -->
          <xsl:variable name="group1"
            select="following-sibling::fb:text-author"/>
          <xsl:variable name="group2"
            select="$first_non_text_author/preceding-sibling::fb:text-author"/>
          <xsl:apply-templates
            select=". | $group1[count(.|$group2) = count($group2)]"
            mode="grouped"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates
            select=". | following-sibling::fb:text-author"
            mode="grouped"/>
        </xsl:otherwise>
      </xsl:choose>
    </subscription>
  </xsl:template>

  <xsl:template match="fb:text-author" mode="grouped">
    <p><xsl:apply-templates/></p>
  </xsl:template>

	<xsl:template match="fb:text-author[parent::fb:cite[parent::fb:section[ancestor::fb:body[@name='notes']]]]">
		<p><xsl:apply-templates/></p>
	</xsl:template>

  <xsl:template match="fb:text-author"/>
  
  <xsl:template match="fb:p">
    <p>
      <xsl:apply-templates/>
    </p>
  </xsl:template>
  
  <xsl:template match="fb:empty-line">
    <br/>
  </xsl:template>
  
  <xsl:template match="fb:poem">
    <!-- poem must consist of at least one stanza element with a nested v element -->
    <xsl:if test="fb:stanza/fb:v">
      <poem>
        <xsl:copy-of select="@id"/>
        <xsl:call-template name="TitledType"/>
        <xsl:apply-templates select="fb:stanza"/>
        <xsl:apply-templates select="fb:text-author"/>
      </poem>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="fb:stanza">
    <xsl:call-template name="PHolderType">
      <xsl:with-param name="holder-name">stanza</xsl:with-param>
      <xsl:with-param name="paragraph-name">v</xsl:with-param>
    </xsl:call-template>
  </xsl:template>
  
  <xsl:template match="fb:v">
    <p><xsl:apply-templates/></p>
  </xsl:template>
  
  <xsl:template match="fb:strong">
    <strong><xsl:apply-templates/></strong>
  </xsl:template>
  
  <xsl:template match="fb:emphasis">
    <em><xsl:apply-templates/></em>
  </xsl:template>
  
  <xsl:template match="fb:strikethrough">
    <strikethrough><xsl:apply-templates/></strikethrough>
  </xsl:template>
  
  <xsl:template match="fb:sub">
    <sub><xsl:apply-templates/></sub>
  </xsl:template>
  
  <xsl:template match="fb:sup">
    <sup><xsl:apply-templates/></sup>
  </xsl:template>
  
  <xsl:template match="fb:code">
    <code><xsl:apply-templates/></code>
  </xsl:template>
  
  <xsl:template match="fb:style">
    <span class="{@name}"><xsl:apply-templates/></span>
  </xsl:template>
  
  <xsl:template match="fb:a">
    <xsl:choose>
      <xsl:when test="@type='note'">
        <xsl:call-template name="note">
          <xsl:with-param name="item" select="."/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <a>
          <xsl:attribute name="xlink:href">
            <xsl:choose>
              <xsl:when test="starts-with(@xlink:href, '#')">
                <xsl:variable name="fb2ID"
                  select="substring-after(@xlink:href, '#')"/>
                <xsl:variable name="fb3ID">
                  <xsl:apply-templates
                    select="//fb:section[@id=$fb2ID]"
                    mode="subsectionID"/>
                </xsl:variable>
                <xsl:value-of select="concat('#',$fb3ID)"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:value-of select="@xlink:href"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:attribute>
          <xsl:apply-templates/>
        </a>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

	<xsl:template match="fb:div">
		<div>
			<xsl:copy-of select="@*"/>
			<xsl:apply-templates/>
		</div>
  </xsl:template>

  <xsl:template match="fb:image">
    <xsl:choose>
      <xsl:when test="parent::fb:section[ancestor::fb:body[@name='notes']]">
        <p>
          <xsl:call-template name="image"/>
        </p>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="image"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="image">
    <xsl:variable name="href"
      select="concat('img', string(count(preceding::fb:image)+1))"/>

    <img src="{$href}">
      <xsl:if test="@id">
        <xsl:attribute name="id">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:variable name="alt-text" select="@alt | @title"/>
      <xsl:if test="$alt-text">
        <xsl:attribute name="alt">
          <xsl:value-of select="$alt-text"/>
        </xsl:attribute>
      </xsl:if>
    </img>
  </xsl:template>
	
	<xsl:template name="title-image">
    <xsl:variable name="href"
      select="concat('img', string(count(preceding::fb:image)))"/>
    <img src="{$href}">
      <xsl:if test="@id">
        <xsl:attribute name="id">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
			<xsl:variable name="alt-text" select="@alt | @title"/>
      <xsl:if test="$alt-text">
        <xsl:attribute name="alt">
          <xsl:value-of select="$alt-text"/>
        </xsl:attribute>
      </xsl:if>
    </img>
  </xsl:template>
  
  <xsl:template match="fb:body[@name='notes']">
    <xsl:variable name="root_sections_count" select="count(fb:section[fb:section])"/>
    <xsl:choose>
      <xsl:when test="root_sections_count >= 2 and not(fb:section[@id])">
        <!-- two (or more) root sections structure. First root section is for
          footnotes and others - for endnotes -->

        <!-- footnotes -->
        <xsl:variable name="footnotes" select="fb:section[1]/fb:section[@id]"/>
        <xsl:if test="$footnotes">
          <notes show="0">
            <xsl:apply-templates select="$footnotes/../fb:title"/>
            <xsl:apply-templates select="$footnotes"/>
          </notes>
        </xsl:if>

        <!-- endnotes -->
        <xsl:variable name="endnotes"
          select="fb:section[preceding-sibling::fb:section]/fb:section"/>
        <xsl:if test="$endnotes">
          <notes show="1">
            <xsl:apply-templates select="$endnotes/../fb:title"/>
            <xsl:apply-templates select="$endnotes"/>
          </notes>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <!-- no root sections structure - only footnotes -->
        <xsl:variable name="footnotes" select=".//fb:section[@id]"/>
        <xsl:if test="$footnotes">
          <notes show="0">
            <xsl:apply-templates select="fb:title"/>
            <xsl:apply-templates select="$footnotes"/>
          </notes>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="fb:table">
    <table>
      <xsl:if test="@id">
        <xsl:attribute name="id">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:apply-templates/>
    </table>
  </xsl:template>

  <xsl:template match="fb:tr">
    <tr>
      <xsl:if test="@id">
        <xsl:attribute name="id">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:if test="@align">
        <xsl:attribute name="align">
          <xsl:value-of select="@align"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:apply-templates/>
    </tr>
  </xsl:template>

  <xsl:template match="fb:th">
    <th><xsl:call-template name="tdType"/></th>
  </xsl:template>

  <xsl:template match="fb:td">
    <td><xsl:call-template name="tdType"/></td>
  </xsl:template>

  <xsl:template name="tdType">
    <xsl:if test="@colspan">
      <xsl:attribute name="colspan">
        <xsl:value-of select="@colspan"/>
      </xsl:attribute>
    </xsl:if>
    <xsl:if test="@rowspan">
      <xsl:attribute name="rowspan">
        <xsl:value-of select="@rowspan"/>
      </xsl:attribute>
    </xsl:if>
    <xsl:if test="@align">
      <xsl:attribute name="align">
        <xsl:value-of select="@align"/>
      </xsl:attribute>
    </xsl:if>
    <xsl:if test="@valign">
      <xsl:attribute name="valign">
        <xsl:value-of select="@valign"/>
      </xsl:attribute>
    </xsl:if>
    <p><xsl:apply-templates/></p>
  </xsl:template>
  
  <!-- image (binary files) and stylesheets are placed outside of xml, so here
  we just skip them -->
  <xsl:template match="fb:binary | fb:stylesheet"/>
  
  <xsl:template name="note">
    <xsl:param name="item"/>
    <xsl:variable name="href" select="substring-after($item/@xlink:href, '#')"/>
    <xsl:variable name="target"
      select="/fb:FictionBook/fb:body[@name='notes']//fb:section[@id=$href][1]"/>
    <xsl:variable name="role">
      <xsl:choose>
        <xsl:when test="$target/parent::fb:body or
          not($target/ancestor::fb:section[parent::fb:body]/preceding-sibling::fb:section)">
          <xsl:text>footnote</xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:text>endnote</xsl:text>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <note href="{$href}" xlink:role="{$role}">
			<xsl:apply-templates/>
		</note>
  </xsl:template>

	<xsl:template match="fb:a[@type='note']//text()">
    <xsl:value-of select="."/>
  </xsl:template>
  
  <xsl:template match="fb:section" mode="subsectionID">
    <xsl:variable name="num">
      <xsl:number level='any' count='fb:section' />
    </xsl:variable>
    <xsl:variable name="base" select="'FFFF'"/>
    <xsl:value-of select="concat($preID, '-', $num, substring($base, string-length($num)+1), '-', $posID)"/>
  </xsl:template>
  
  <xsl:template name="tokenize">
    <xsl:param name="str"/>
    <xsl:param name="delim"/>
    <xsl:choose>
      <xsl:when test="contains($str, $delim)">
        <xsl:element name="str">
          <xsl:value-of select="substring-before($str, $delim)"/>
        </xsl:element>
        <xsl:call-template name="tokenize">
          <xsl:with-param name="str" select="substring-after($str, $delim)"/>
          <xsl:with-param name="delim" select="$delim"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$str"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
</xsl:stylesheet>
