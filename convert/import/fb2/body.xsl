<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xlink="http://www.w3.org/1999/xlink"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0"
    xmlns="http://www.fictionbook.org/FictionBook3/body"
    exclude-result-prefixes="fb">
    
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    
    <xsl:variable name="description" select="/fb:FictionBook/fb:description"/>
    
    <xsl:variable name="globalID">
        <xsl:value-of select="$description/fb:document-info/fb:id/text()"/>
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
        <fb3-body xsi:noNamespaceSchemaLocation="./schema/fb3_body.xsd"  id="{$globalID}">
            <xsl:apply-templates/>
        </fb3-body>
    </xsl:template>
    
    <xsl:template match="/fb:FictionBook/fb:description"/>
    
    <xsl:template match="fb:body[not(@name)]">
        <section id="{$globalID}">
            <xsl:apply-templates/>
        </section>
    </xsl:template>
    
    <xsl:template match="fb:section">
        <xsl:choose>
<!--            основная секция сносок - без id-->
            <xsl:when test="ancestor::fb:body[1]/@name='notes'  and not(@id)">
                <xsl:apply-templates select="fb:section"/>
            </xsl:when>
<!--            сноски с id внутри блока сносок-->
            <xsl:when test="ancestor::fb:body[1]/@name='notes'  and @id">
                <note id="{@id}">
                    <xsl:apply-templates/>
                </note>
            </xsl:when>
            <xsl:otherwise>
<!--                обычная секция в тексте-->
                <section>
                    <xsl:variable name="num">
                        <xsl:number level='any' count='fb:section' />
                    </xsl:variable>
                    <xsl:variable name="pre" select="substring-before($globalID, '-')"/>
                    <xsl:variable name="pos" select="substring-after(substring-after($globalID, '-'), '-')"/>
                    <xsl:attribute name="id">
                        <xsl:call-template name="subsectionID">
                            <xsl:with-param name="item" select="."/>
                            <xsl:with-param name="num" select="$num"/>
                        </xsl:call-template>
                    </xsl:attribute>
                    <xsl:apply-templates/>
                </section>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
    <xsl:template match="fb:title">
        <title>
            <xsl:apply-templates/>
        </title>
    </xsl:template>
    
    <xsl:template match="fb:subtitle">
        <subtitle>
            <xsl:apply-templates/>
        </subtitle>
    </xsl:template>
    
    <xsl:template match="fb:epigraph">
        <epigraph>
            <xsl:apply-templates/>
        </epigraph>
    </xsl:template>
    
    <xsl:template match="fb:annotation">
        <annotation><xsl:apply-templates/></annotation>
    </xsl:template>
    
<!--    тимплейт для часто встречающейся конструкции cite/text-author-->
    <xsl:template match="fb:cite[count(*)=1 and fb:text-author]">
        <xsl:apply-templates/>
    </xsl:template>
    
    <xsl:template match="fb:cite">
        <blockquote>
            <xsl:apply-templates/>
        </blockquote>
    </xsl:template>
    
    <xsl:template match="fb:text-author">
        <subscription>
            <p><xsl:apply-templates/></p>
        </subscription>
    </xsl:template>
    
    <xsl:template match="fb:p">
        <p>
            <xsl:apply-templates/>
        </p>
    </xsl:template>
    
    <xsl:template match="fb:empty-line">
        <br/>
    </xsl:template>
    
    <xsl:template match="fb:poem">
        <poem>
            <xsl:apply-templates/>
        </poem>
    </xsl:template>
    
    <xsl:template match="fb:stanza">
        <stanza>
            <xsl:apply-templates/>
        </stanza>
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
    
    <xsl:template match="fb:underline">
        <underline><xsl:apply-templates/></underline>
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
    
    <xsl:template match="fb:image">
        <xsl:variable name="href" select="concat('img', string(count(preceding::fb:image)+1))"/>
        <xsl:choose>
            <xsl:when test="parent::fb:section">
                <div float="center">
                    <p>
                        <img src="{$href}" width="60em"/>
                    </p>
                </div>
            </xsl:when>
            <xsl:otherwise>
                <img src="{$href}" width="10em"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
    <xsl:template match="fb:body[@name='notes']">
        <notes>
            <xsl:apply-templates/>
        </notes>
    </xsl:template>
  
    <xsl:template match="fb:binary"/>
    
    <xsl:template name="note">
        <xsl:param name="item"/>
        <xsl:variable name="href" select="substring-after($item/@*[name()='l:href'], '#')"/>
        <xsl:variable name="text">
            <xsl:choose>
                <xsl:when test="starts-with($item/text(), '[')">
                    <xsl:value-of select="substring-before(substring-after($item/text(), '['), ']')"/>
                </xsl:when>
                <xsl:when test="starts-with($item/text(), '{')">
                    <xsl:value-of select="substring-before(substring-after($item/text(), '{'), '}')"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="text()"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:variable name="role">
            <xsl:choose>
                <xsl:when test="starts-with($href, 'n')">
                    <xsl:text>footnote</xsl:text>
                </xsl:when>
                <xsl:when test="starts-with($href, 'c')">
                    <xsl:text>comment</xsl:text>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:text>auto</xsl:text>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <note href="{$href}" xlink:role="{$role}"><xsl:value-of select="$text"/></note>
    </xsl:template>
    
    <xsl:template name="subsectionID">
        <xsl:param name="item"/>
        <xsl:param name="num"/>
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