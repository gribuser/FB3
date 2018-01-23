<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:fb3d="http://www.fictionbook.org/FictionBook3/description" xmlns:l="http://www.w3.org/1999/xlink" xmlns:ltr="LTR">
<xsl:output method="xml" encoding="UTF-8"/>
  
	<xsl:template match="/">
		<description>
			<xsl:apply-templates/>
		</description>
	</xsl:template>
  
	<xsl:template match="fb3d:fb3-description">
		<title-info>
			<xsl:apply-templates select="fb3d:fb3-classification/fb3d:subject" mode="genre"/>
			<xsl:apply-templates select="fb3d:fb3-relations/fb3d:subject[@link = 'author']"/>
			<xsl:apply-templates select="fb3d:title"/>
			<xsl:apply-templates select="fb3d:annotation"/>
			<xsl:apply-templates select="fb3d:keywords"/>
			<xsl:apply-templates select="fb3d:written"/>
			<xsl:apply-templates select="fb3d:coverpage"/>
			<xsl:apply-templates select="fb3d:lang"/>
			<xsl:apply-templates select="fb3d:written" mode="src-lang"/>
			<xsl:apply-templates select="fb3d:fb3-relations/fb3d:subject[@link = 'translator']"/>
			<xsl:apply-templates select="fb3d:sequence"/>
		</title-info>
		<document-info>
			<xsl:apply-templates select="fb3d:document-info"/>			
			<id><xsl:value-of select="@id"/></id>
			<version><xsl:value-of select="@version"/></version>
			<xsl:apply-templates select="fb3d:history"/>
		</document-info>
		<xsl:apply-templates select="fb3d:paper-publish-info"/>
		<xsl:apply-templates select="fb3d:custom-info"/>
		<xsl:apply-templates select="fb3d:periodical" mode="custom-info"/>	
		<xsl:apply-templates select="fb3d:title" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:sequence" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:fb3-classification" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:written[fb3d:country or fb3d:date-public]" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:translated" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:copyrights" mode="custom-info"/>
		<xsl:apply-templates select="fb3d:paper-publish-info/fb3d:biblio-description" mode="paper-custom-info">
			<xsl:with-param name="path">fb3d:fb3-description/fb3d:paper-publish-info/fb3d:biblio-description</xsl:with-param>
		</xsl:apply-templates>
	</xsl:template>
  
 	<xsl:template match="fb3d:fb3-classification/fb3d:subject" mode="genre">
		<genre><xsl:call-template name="lower"><xsl:with-param name="str"><xsl:value-of select="text()"/></xsl:with-param></xsl:call-template></genre>
	</xsl:template>
	
 	<xsl:template match="fb3d:fb3-relations/fb3d:subject[@link = 'author' or @link = 'translator']">
		<xsl:variable name="tag-name">
			<xsl:choose>
				<xsl:when test="@link = 'author'">author</xsl:when>
				<xsl:when test="@link = 'translator'">translator</xsl:when>
				<xsl:otherwise/>
			</xsl:choose>
		</xsl:variable>
		<xsl:if test="$tag-name and $tag-name != ''">
			<xsl:element name="{$tag-name}">
				<first-name><xsl:value-of select="fb3d:first-name"/></first-name>
				<xsl:if test="fb3d:middle-name">
					<middle-name><xsl:value-of select="fb3d:middle-name"/></middle-name>
				</xsl:if>
				<last-name><xsl:value-of select="fb3d:last-name"/></last-name>
				<id><xsl:value-of select="@id"/></id>
			</xsl:element>
		</xsl:if>
	</xsl:template>
	
	<xsl:template match="fb3d:coverpage">
		<coverpage><image l:href="{concat('#',ltr:RplId(@href))}"/></coverpage>
	</xsl:template>
	
	<xsl:template match="fb3d:title">
		<book-title><xsl:value-of select="fb3d:main"/></book-title>
	</xsl:template>
	
	<xsl:template match="fb3d:annotation">
		<annotation><xsl:apply-templates/></annotation>
	</xsl:template>
	
	<xsl:template match="fb3d:keywords">
		<keywords><xsl:apply-templates/></keywords>
	</xsl:template>
	
	<xsl:template match="fb3d:written">
		<xsl:if test="fb3d:date/@value and fb3d:date/@value != ''">
			<date>
				<xsl:attribute name="value"><xsl:value-of select="fb3d:date/@value"/></xsl:attribute>
				<xsl:choose>
					<xsl:when test="fb3d:date/text()"><xsl:apply-templates select="fb3d:date/text()"/></xsl:when>
					<xsl:otherwise><xsl:value-of select="substring(fb3d:date/@value, 1, 4)"/></xsl:otherwise>
				</xsl:choose>				
			</date>
		</xsl:if>		
	</xsl:template>
	
	<xsl:template match="fb3d:written" mode="src-lang">
		<xsl:if test="fb3d:lang and fb3d:lang/text()">
			<src-lang><xsl:apply-templates select="fb3d:lang/text()"/></src-lang>
		</xsl:if>
	</xsl:template>
	
	<xsl:template match="fb3d:lang">
		<lang><xsl:apply-templates/></lang>
	</xsl:template>
	
	<xsl:template match="fb3d:sequence">
		<sequence>
			<xsl:attribute name="name"><xsl:apply-templates select="fb3d:title/fb3d:main"/></xsl:attribute>
			<xsl:if test="@number">
				<xsl:attribute name="number"><xsl:value-of select="@number"/></xsl:attribute>
			</xsl:if>
			<xsl:apply-templates select="fb3d:sequence"/>
		</sequence>
	</xsl:template>
	
	<xsl:template match="fb3d:document-info">
		<xsl:variable name="editor">
			<xsl:choose>
				<xsl:when test="@editor and @editor != ''"><xsl:value-of select="@editor"/></xsl:when>
				<xsl:otherwise>Аноним</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>
		<author>
			<nickname><xsl:value-of select="$editor"/></nickname>
		</author>
		
		<xsl:if test="@program-used and @program-used != ''">
			<program-used><xsl:value-of select="@program-used"/></program-used>
		</xsl:if>
		
		<xsl:variable name="created_y"><xsl:value-of select="substring(@created,1,4)"/></xsl:variable>	
		<xsl:variable name="created_m"><xsl:value-of select="substring(@created,6,2)"/></xsl:variable>	
		<xsl:variable name="created_d"><xsl:value-of select="substring(@created,9,2)"/></xsl:variable>	
		
		<date>
			<xsl:attribute name="value"><xsl:value-of select="concat($created_y,'-',$created_m,'-',$created_d)"/></xsl:attribute>
			<xsl:value-of select="concat($created_d,'.',$created_m,'.',$created_y)"/>
		</date>
		<xsl:if test="@src-url">
			<src-url><xsl:value-of select="@src-url"/></src-url>
		</xsl:if>
		<xsl:if test="@ocr">
			<src-ocr><xsl:value-of select="@ocr"/></src-ocr>
		</xsl:if>
	</xsl:template>
	
	<xsl:template match="fb3d:history">
		<history>
			<xsl:apply-templates/>
		</history>
	</xsl:template>
	
	<xsl:template match="fb3d:paper-publish-info">
		<publish-info>
			<book-name><xsl:value-of select="@title"/></book-name>
			<xsl:if test="@publisher">
				<publisher><xsl:value-of select="@publisher"/></publisher>
			</xsl:if>
			<xsl:if test="@city">
				<city><xsl:value-of select="@city"/></city>
			</xsl:if>
			<xsl:if test="@year">
				<year><xsl:value-of select="@year"/></year>
			</xsl:if>
			<xsl:if test="fb3d:isbn">
				<isbn><xsl:apply-templates select="fb3d:isbn"/></isbn>
			</xsl:if>
			<xsl:if test="fb3d:sequence">				
				<xsl:apply-templates select="fb3d:sequence" mode="paper-publish-info"/>
			</xsl:if>			
		</publish-info>
	</xsl:template>
	
	<xsl:template match="fb3d:custom-info">
		<custom-info>
			<xsl:attribute name="info-type"><xsl:value-of select="@info-type"/></xsl:attribute>
			<xsl:apply-templates/>
		</custom-info>
	</xsl:template>
	
	<xsl:template match="fb3d:sequence" mode="paper-publish-info">
		<sequence>
			<xsl:attribute name="name"><xsl:apply-templates/></xsl:attribute>
			<!-- в FBEditor отсутствует поле для номера серии -->
		</sequence>
	</xsl:template>

	<xsl:template match="*"  mode="custom-info">
		<xsl:param name="path">fb3d:fb3-description/fb3d:<xsl:value-of select="name()"/></xsl:param>
		<xsl:variable name="node" select="name()"/>
		<xsl:for-each select="@*">
			<xsl:if test="not(name(.) = 'number') and $node = 'sequence'">
				<custom-info>
					<xsl:attribute name="info-type"><xsl:value-of select="$path"/>/@<xsl:value-of select="name()"/></xsl:attribute>
					<xsl:value-of select="."/>
				</custom-info>
			</xsl:if>
		</xsl:for-each>
		
		<xsl:for-each select="*[not(name() = 'main' or name() = 'subject')]">
			<xsl:if test="string-length(normalize-space(text())) &gt; 0">
				<custom-info>
					<xsl:attribute name="info-type"><xsl:value-of select="$path"/>/fb3d:<xsl:value-of select="name()"/></xsl:attribute>
					<xsl:copy-of select="normalize-space(text())"/>
				</custom-info>
			</xsl:if>
			<xsl:for-each select="@*">
				<xsl:if test="not(name(.) = 'number') and $node = 'sequence'">
					<custom-info>
						<xsl:attribute name="info-type"><xsl:value-of select="$path"/>/fb3d:<xsl:value-of select="name(parent::*)"/>/@<xsl:value-of select="name()"/></xsl:attribute>
						<xsl:value-of select="."/>
					</custom-info>
				</xsl:if>
			</xsl:for-each>
			<xsl:if test="descendant::*">
				<xsl:for-each select="descendant::*[not(name() = 'main' and $node = 'sequence')]">
					<xsl:if test="string-length(normalize-space(text())) &gt; 0">
						<custom-info>
							<xsl:attribute name="info-type"><xsl:value-of select="$path"/>/@<xsl:value-of select="name()"/></xsl:attribute>
							<xsl:copy-of select="normalize-space(text())"/>
						</custom-info>
					</xsl:if>
				</xsl:for-each>
			</xsl:if>			
		</xsl:for-each>
	</xsl:template>
	
	<xsl:template match="fb3d:paper-publish-info/fb3d:biblio-description" mode="paper-custom-info">
		<xsl:param name="path"/>
		<custom-info>
			<xsl:attribute name="info-type"><xsl:value-of select="$path"/></xsl:attribute>
			<xsl:apply-templates mode="paper-custom-info"/>
		</custom-info>	
	</xsl:template>
	
	<xsl:template match="fb3d:p">
		<p><xsl:apply-templates/></p>
	</xsl:template>
	
	<xsl:template match="fb3d:p" mode="paper-custom-info">
		<xsl:value-of select="normalize-space(.)"/>
		<xsl:if test="position() != last()"><xsl:text> </xsl:text></xsl:if>
	</xsl:template>
	
	<xsl:template match="*" mode="paper-custom-info"/>

	<xsl:template match="fb3d:br">
		<empty-line />
	</xsl:template>
	
	<xsl:template match="fb3d:strong">
		<strong><xsl:apply-templates/></strong>
	</xsl:template>
	
	<xsl:template match="fb3d:em">
		<emphasis><xsl:apply-templates/></emphasis>
	</xsl:template>
	
	<xsl:template match="fb3d:a">
		<a>
			<xsl:attribute name="l:href"><xsl:value-of select="@href"/></xsl:attribute>
			<xsl:apply-templates/>
		</a>
	</xsl:template>

	<xsl:template match="fb3d:subject"/>
  
	 <xsl:template name="lower">
		<xsl:param name="str"/>
		<xsl:variable name="lowCase">абвгдеёжзийклмнопрстуфхцчшщыъьэюяabcdefghijklmnopqrstuvwxyz</xsl:variable>
		<xsl:variable name="upCase">АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЫЪЬЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ</xsl:variable>
		<xsl:value-of select="translate($str, $upCase, $lowCase)"/>
	</xsl:template>
</xsl:stylesheet>
