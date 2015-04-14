<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    version="1.0">
    
    <xsl:template name="UUID">
        <xsl:value-of select="'00000000-0000-0000-0000-000000000000'"/>
    </xsl:template>
    
    <xsl:template name="date-format">
        <xsl:param name="date"/>
        <xsl:value-of select="$date"/>
    </xsl:template>
    
</xsl:stylesheet>