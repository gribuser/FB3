<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0"
    xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:dcterms="http://purl.org/dc/terms/"
    xmlns:dcmitype="http://purl.org/dc/dcmitype/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    exclude-result-prefixes="fb">
    
    <xsl:include href="general.xsl"/>
    
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    
    <xsl:variable name="description" select="/fb:FictionBook/fb:description"/>
    <xsl:variable name="docinfo" select="$description/fb:document-info"/>
    
    <xsl:variable name="globalID">
        <xsl:value-of select="$description/fb:document-info/fb:id/text()"/>
    </xsl:variable>
    
    
    <xsl:template match="/">
        <cp:coreProperties>
            <dc:title><xsl:variable name="title" select="$description/fb:title-info/fb:book-title/text()"/></dc:title>
            <dc:subject><xsl:apply-templates select="$description/fb:title-info/fb:annotation/*"/></dc:subject>
            <dc:creator>
                <xsl:value-of select="normalize-space(concat($docinfo/fb:author/fb:first-name/text(), ' ', $docinfo/fb:author/fb:last-name/text()))"/>
            </dc:creator>
            <dc:description><xsl:apply-templates select="$description/fb:title-info/fb:annotation/*"/></dc:description>
            <cp:keywords>XML, FictionBook, eBook, OPC</cp:keywords>
            <cp:revision>1.00</cp:revision>
            <xsl:if test="$docinfo/fb:date/@value">
                <dcterms:created xsi:type="dcterms:W3CDTF">
                    <xsl:call-template name="date-format">
                        <xsl:with-param name="date">
                            <xsl:value-of select="$docinfo/fb:date/@value"/>
                        </xsl:with-param>
                    </xsl:call-template>
                </dcterms:created>
            </xsl:if>
            <cp:contentStatus>Draft</cp:contentStatus>
            <cp:category>
                <xsl:for-each select="$description/fb:title-info/fb:genre">
                    <xsl:value-of select="./text()"/>
                    <xsl:if test="position()!=last()">
                        <xsl:text xml:space="preserve"> </xsl:text>
                    </xsl:if>
                </xsl:for-each>
            </cp:category>
        </cp:coreProperties>
    </xsl:template>
            
    <xsl:template match="fb:p">
        <xsl:apply-templates/>
    </xsl:template>
    
    <xsl:template match="fb:br"/>
    
</xsl:stylesheet>
