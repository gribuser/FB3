<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
		xmlns:l="http://www.w3.org/1999/xlink"
		xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"
		xmlns:fb3b="http://www.fictionbook.org/FictionBook3/body"
		xmlns:ltr="LTR">
	<xsl:output method="xml" encoding="UTF-8"/>

	<xsl:template match="/">
		<xsl:apply-templates/>
	</xsl:template>

	<xsl:template match="fb3b:fb3-body">
		<root>
			<body>
				<xsl:apply-templates select="fb3b:title"/>
				<xsl:apply-templates select="fb3b:epigraph"/>
				<xsl:apply-templates select="fb3b:preamble"/>
				<xsl:apply-templates select="fb3b:section"/>
			</body>
			<xsl:choose>
				<xsl:when test="count(fb3b:notes) &gt; 1">
					<body name="notes">
						<xsl:apply-templates select="fb3b:notes" mode="many_notes">
							<xsl:sort data-type="number" case-order="upper-first" select="@show" order="descending"/>
						</xsl:apply-templates>
					</body>
				</xsl:when>
				<xsl:otherwise>
					<xsl:apply-templates select="fb3b:notes"/>
				</xsl:otherwise>
			</xsl:choose>
		</root>
	</xsl:template>

	<xsl:template match="fb3b:title">
		<xsl:choose>
			<xsl:when test="parent::fb3b:blockquote">
				<subtitle><xsl:apply-templates/></subtitle>
			</xsl:when>
			<xsl:otherwise>
				<title><xsl:apply-templates/></title>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="fb3b:title" mode="notes">
		<xsl:choose>
			<xsl:when test="parent::fb3b:blockquote">
				<subtitle><xsl:apply-templates/></subtitle>
			</xsl:when>
			<xsl:otherwise>
				<title><xsl:apply-templates/></title>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="fb3b:subtitle">
		<subtitle>
			<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="@id"/></xsl:attribute></xsl:if>
			<xsl:apply-templates/>
		</subtitle>
	</xsl:template>

	<xsl:template match="fb3b:annotation">
		<annotation><xsl:apply-templates/></annotation>
	</xsl:template>

	<xsl:template match="fb3b:p">
		<xsl:variable name="noimgtags_inside"><xsl:value-of select="count(*[name() != 'img'])"/></xsl:variable>
		<xsl:variable name="images_inside"><xsl:value-of select="count(fb3b:img)"/></xsl:variable>
		<xsl:variable name="p_text"><xsl:value-of select="normalize-space(.)"/></xsl:variable>
		<xsl:choose>
			<xsl:when test="$images_inside = 1 and $noimgtags_inside = 0 and string-length($p_text) = 0">
				<xsl:apply-templates/>
				<xsl:if test="not(parent::fb3b:div)">
					<empty-line/>
				</xsl:if>
			</xsl:when>
			<xsl:when test="parent::fb3b:title[parent::fb3b:blockquote]">
				<xsl:apply-templates/>
			</xsl:when>
			<xsl:otherwise>
				<p>
					<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="@id"/></xsl:attribute></xsl:if>
					<xsl:apply-templates/>
				</p>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="fb3b:subscription">
		<xsl:apply-templates/>
	</xsl:template>

	<xsl:template match="fb3b:preamble">
			<section>
				<xsl:apply-templates/>
			</section>
	</xsl:template>
	
	<xsl:template match="fb3b:section">
		<section>
			<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="@id"/></xsl:attribute></xsl:if>
			<xsl:apply-templates/>
		</section>
	</xsl:template>

	<xsl:template match="fb3b:epigraph">
		<epigraph><xsl:apply-templates/></epigraph>
	</xsl:template>

	<xsl:template match="fb3b:br">
		<empty-line/>
	</xsl:template>

	<xsl:template match="fb3b:pre">
		<cite>
			<p><code><xsl:apply-templates/></code></p>
		</cite>
	</xsl:template>

	<xsl:template match="fb3b:blockquote">
		<cite>
			<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="@id"/></xsl:attribute></xsl:if>
			<xsl:apply-templates/>
		</cite>
	</xsl:template>

	<xsl:template match="fb3b:div[not(@on-one-page = 'true')]">
		<xsl:choose>
			<xsl:when test="fb3b:p[fb3b:img and string-length(normalize-space(.)) = 0]">
				<xsl:apply-templates/>
				<empty-line/>
			</xsl:when>
			<xsl:otherwise>
				<cite>
					<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="@id"/></xsl:attribute></xsl:if>
					<xsl:apply-templates/>
				</cite>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="fb3b:div[@on-one-page = 'true']">
		<xsl:apply-templates/>
		<empty-line/>
	</xsl:template>

	<xsl:template match="fb3b:img">
		<image l:href="{concat('#', ltr:RplId(@src))}">
			<xsl:if test="@alt"><xsl:attribute name="alt"><xsl:value-of select="@alt"/></xsl:attribute></xsl:if>
			<xsl:if test="@id"><xsl:attribute name="id">u<xsl:value-of select="ltr:RplId(@id)"/></xsl:attribute></xsl:if>
		</image>
	</xsl:template>

	<xsl:template match="fb3b:span">
		<xsl:apply-templates/>
	</xsl:template>
	<xsl:template match="fb3b:strong">
		<strong><xsl:apply-templates/></strong>
	</xsl:template>
	<xsl:template match="fb3b:em">
		<emphasis><xsl:apply-templates/></emphasis>
	</xsl:template>
	<xsl:template match="fb3b:sub">
		<sub><xsl:apply-templates/></sub>
	</xsl:template>
	<xsl:template match="fb3b:sup">
		<sup><xsl:apply-templates/></sup>
	</xsl:template>
	<xsl:template match="fb3b:strikethrough">
		<strikethrough><xsl:apply-templates/></strikethrough>
	</xsl:template>
	<!-- dont have in fb2, just kill -->
	<xsl:template match="fb3b:underline|fb3b:spacing|fb3b:marker|fb3b:paper-page-break">
		<xsl:apply-templates/>
	</xsl:template>

	<xsl:template match="fb3b:a">
		<a l:href="{ltr:RplId(@l:href)}"><xsl:apply-templates/></a>
	</xsl:template>

	<xsl:template match="fb3b:note">
		<a l:href="#u{@href}" type="note"><xsl:apply-templates/></a>
	</xsl:template>

	<xsl:template match="fb3b:code">
		<xsl:choose>
			<xsl:when test="ancestor::fb3b:stanza">
				<xsl:apply-templates/>
			</xsl:when>
			<xsl:otherwise>
				<code><xsl:apply-templates/></code>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="fb3b:poem">
		<poem>
			<xsl:apply-templates mode="poem"/>
		</poem>
	</xsl:template>
	<xsl:template match="*" mode="poem">
		<xsl:apply-templates select="."/>
	</xsl:template>
	<xsl:template match="fb3b:subscription" mode="poem">
		<text-author>
			<xsl:apply-templates mode="poem_subscription"/>
		</text-author>
	</xsl:template>
	<xsl:template match="fb3b:p|fb3b:ul/fb3b:li|fb3b:ol/fb3b:li" mode="poem_subscription">
		<xsl:if test="position() != 1"><xsl:text>  </xsl:text></xsl:if>
		<xsl:apply-templates/>
	</xsl:template>
	<xsl:template match="fb3b:br" mode="poem_subscription"/>

	<xsl:template match="fb3b:stanza">
		<stanza>
			<xsl:apply-templates mode="stanza"/>
		</stanza>
	</xsl:template>
	<xsl:template match="fb3b:p" mode="stanza">
		<v><xsl:apply-templates/></v>
	</xsl:template>
	<xsl:template match="fb3b:br" mode="stanza"/>

	<xsl:template match="fb3b:table">
		<table><xsl:apply-templates/></table>
	</xsl:template>
	<xsl:template match="fb3b:tr">
		<tr><xsl:apply-templates/></tr>
	</xsl:template>
	<xsl:template match="fb3b:th">
		<th><xsl:apply-templates/></th>
	</xsl:template>
	<xsl:template match="fb3b:td">
		<td><xsl:apply-templates/></td>
	</xsl:template>
  <xsl:template match="fb3b:td/fb3b:p">
		<xsl:apply-templates/>
	</xsl:template>

	<xsl:template match="fb3b:ul">
		<cite><xsl:apply-templates>
			<xsl:with-param name="prefix" select="@type"/>
		</xsl:apply-templates></cite>
	</xsl:template>
	<xsl:template match="fb3b:ol">
		<cite><xsl:for-each select="fb3b:li">
			<xsl:apply-templates select=".">
				<xsl:with-param name="prefix" select="position()"/>
			</xsl:apply-templates>
		</xsl:for-each></cite>
	</xsl:template>
	<xsl:template match="fb3b:li">
		<xsl:param name="prefix">&#8226;</xsl:param>
		<p><xsl:value-of select="$prefix"/>&#160;<xsl:apply-templates/></p>
	</xsl:template>

	<xsl:template match="fb3b:notes">
		<body name="notes"><xsl:apply-templates mode="notes"/></body>
	</xsl:template>
	<xsl:template match="fb3b:notes" mode="many_notes">
		<section><xsl:apply-templates mode="notes"/></section>
	</xsl:template>
	<xsl:template match="fb3b:notebody" mode="notes">
		<section id="u{@id}"><xsl:apply-templates/></section>
	</xsl:template>

</xsl:stylesheet>
