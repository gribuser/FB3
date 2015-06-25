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
    
    <xsl:variable name="globalID">
        <xsl:value-of select="$description/fb:document-info/fb:id/text()"/>
    </xsl:variable>
    
    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>
    
    <xsl:template match="/">
        <xsl:variable name="uuid">
            <xsl:call-template name="UUID"/>
        </xsl:variable>
        <fb3-description xsi:noNamespaceSchemaLocation="./schema/fb3_descr.xsd"  id="{$uuid}"  version="1.0">
            <xsl:call-template name="title"/>
            <xsl:call-template name="sequence"/>
            <xsl:call-template name="relations"/>
            <xsl:call-template name="classification"/>
            <xsl:call-template name="lang"/>
            <xsl:call-template name="written"/>
            <xsl:call-template name="document-info"/>
            <xsl:call-template name="keywords"/>
            <xsl:call-template name="publish-info"/>
            <xsl:call-template name="custom-info"/>
            <xsl:call-template name="annotation"/>
        </fb3-description>
    </xsl:template>
    
    <xsl:template name="title">
        <xsl:variable name="title" select="$description/fb:title-info/fb:book-title/text()"/>
        <title>
            <main><xsl:value-of select="$title"/></main>
            <sub><xsl:value-of select="$title"/></sub>
            <alt><xsl:value-of select="$title"/></alt>
        </title>
    </xsl:template>
    
    <xsl:template name="sequence">
        <xsl:variable name="uuid">
            <xsl:call-template name="UUID"/>
        </xsl:variable>
        <xsl:variable name="title" select="$description/fb:title-info/fb:book-title/text()"/>
        <sequence number="1" id="{$uuid}">
            <title><main><xsl:value-of select="$title"/></main></title>
        </sequence>
    </xsl:template>
    
    <xsl:template name="relations">
        <xsl:variable name="author" select="$description/fb:title-info/fb:author"/>
        <xsl:variable name="authorID" select="$author/fb:id/text()"/>
        <relations>
            <subject id="{$authorID}" link="author">
                <title>
                    <xsl:variable name="first-last" select="concat($author/fb:first-name/text(), ' ', $author/fb:last-name/text())"/>
                    <main><xsl:value-of select="$first-last"/></main>
                    <sub><xsl:value-of select="$first-last"/></sub>
                    <alt><xsl:value-of select="$first-last"/></alt>
                </title>
                <first-name><xsl:value-of select="$author/fb:first-name/text()"/></first-name>
                <middle-name><xsl:value-of select="$author/fb:middle-name/text()"/></middle-name>
                <last-name><xsl:value-of select="$author/fb:last-name/text()"/></last-name>
            </subject>
        </relations>
    </xsl:template>
    
    <xsl:template name="classification">
        <classification>
            <xsl:variable name="genres" select="$description/fb:title-info/fb:genre"/>
            <class contents="standalone">novel</class>
            <xsl:for-each select="$genres">
                <subject><xsl:value-of select="text()"/></subject>
            </xsl:for-each>
            <custom-subject/>
            <target-audience age-min="9" age-max="99" education="high">
                Для широкого круга читателей
            </target-audience>
            <setting country="" place="" date="" date-from="" date-to="" age=""/>
            <udk/>
            <bbk/>
        </classification>
    </xsl:template>
    
    <xsl:template name="lang">
        <xsl:variable name="lang" select="$description/fb:title-info/fb:lang/text()"/>
        <lang><xsl:value-of select="$lang"/></lang>
    </xsl:template>
    
    <xsl:template name="written">
        <xsl:variable name="lang" select="$description/fb:title-info/fb:lang/text()"/>
        <xsl:variable name="date" select="$description/fb:title-info/fb:date"/>
        <written>
            <lang><xsl:value-of select="$lang"/></lang>
            <date value="{$date/@value}"><xsl:value-of select="$date/text()"/></date>
            <country>World</country>
        </written>
    </xsl:template>
    
    <xsl:template name="document-info">
        <xsl:variable name="docinfo" select="$description/fb:document-info"/>
        <document-info>
            <xsl:attribute name="created">
                <xsl:call-template name="date-format">
                    <xsl:with-param name="date">
                        <xsl:value-of select="$docinfo/fb:date/@value"/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:attribute>
            <xsl:attribute name="updated">
                <xsl:call-template name="date-format">
                    <xsl:with-param name="date">
                        <xsl:value-of select="$docinfo/fb:date/text()"/>
                    </xsl:with-param>
                </xsl:call-template>
            </xsl:attribute>
            <xsl:attribute name="program-used"><xsl:value-of select="$docinfo/fb:program-used/text()"/></xsl:attribute>
            <xsl:attribute name="src-url"><xsl:value-of select="$docinfo/fb:src-url/text()"/></xsl:attribute>
            <xsl:attribute name="ocr"><xsl:value-of select="$docinfo/fb:ocr/text()"/></xsl:attribute>
            <xsl:attribute name="editor">
                <xsl:value-of select="normalize-space(concat($docinfo/fb:author/fb:first-name/text(), ' ', $docinfo/fb:author/fb:last-name/text()))"/>
            </xsl:attribute>
        </document-info>
    </xsl:template>
    
    <xsl:template name="keywords">
        <keywords/>
    </xsl:template>
    
    <xsl:template name="publish-info">
        <xsl:variable name="pubinfo" select="$description/fb:publish-info"/>
        <publish-info>
            <xsl:attribute name="title"><xsl:value-of select="$pubinfo/fb:book-name/text()"/></xsl:attribute>
            <xsl:attribute name="publisher"><xsl:value-of select="$pubinfo/fb:publisher/text()"/></xsl:attribute>
            <xsl:attribute name="city"><xsl:value-of select="$pubinfo/fb:city/text()"/></xsl:attribute>
            <xsl:attribute name="year"><xsl:value-of select="$pubinfo/fb:year/text()"/></xsl:attribute>
            <xsl:if test="$pubinfo/fb:isbn">
                <xsl:attribute name="isbn"><xsl:value-of select="$pubinfo/fb:isbn/text()"/></xsl:attribute>
            </xsl:if>
        </publish-info>
    </xsl:template>
    
    <xsl:template name="custom-info">
        <custom-info info-type="general">
            Здесь можно расположить дополнительную информацию, не укладывающуюся в заданную схему. 
            Это может быть как описательная информация, так и коммерческая информация, связанная с книгой - например, информация о том, где можно купить бумажное издание
        </custom-info>
    </xsl:template>
    
    <xsl:template name="annotation">
        <annotation>
            <xsl:apply-templates select="$description/fb:title-info/fb:annotation/*"/>
        </annotation>
    </xsl:template>
    
    <xsl:template match="fb:p">
        <p><xsl:apply-templates/></p>
    </xsl:template>
    
    <xsl:template match="fb:br">
        <br/>
    </xsl:template>
    
</xsl:stylesheet>