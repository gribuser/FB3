<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform" 
    xmlns="http://schemas.openxmlformats.org/package/2006/relationships"
    xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0"
    exclude-result-prefixes="fb">
    
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    
    <xsl:template match="/">
        <Relationships>
            <xsl:for-each select="//fb:image">
                <xsl:variable name="id" select="concat('img', string(position()))"/>
                <xsl:variable name="href">
                    <xsl:choose>
                        <xsl:when test="starts-with(@*[name()='l:href'], '#')">
                            <xsl:value-of select="substring-after(@*[name()='l:href'], '#')"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:value-of select="@*[name()='l:href']"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:variable name="target" select="concat('img/', $href)"/>
                <Relationship Id="{$id}" Type="http://www.fictionbook.org/FictionBook3/relationships/image" Target="{$target}"/>
            </xsl:for-each>
        </Relationships>
    </xsl:template>
    
</xsl:stylesheet>