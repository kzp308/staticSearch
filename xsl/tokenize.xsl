<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math"
    xmlns:hcmc="http://hcmc.uvic.ca/ns/staticSearch"
    xmlns:xd="http://www.oxygenxml.com/ns/doc/xsl"
    xmlns="http://www.w3.org/1999/xhtml"
    exclude-result-prefixes="#all"
    xpath-default-namespace="http://www.w3.org/1999/xhtml"
    xmlns:ss="http://hcmc.uvic.ca/ns/ssStemmer"
    version="3.0">
    <xd:doc scope="stylesheet">
        <xd:desc>
            <xd:p><xd:b>Created on:</xd:b> June 26, 2019</xd:p>
            <xd:p><xd:b>Authors:</xd:b> Joey Takeda and Martin Holmes</xd:p>
            <xd:p>This transformation takes the collection of documents specified in the configuration
            file and creates the temporary tokenized and stemmed output HTML files to create the JSON indexes.</xd:p>
            <xd:p>Broadly, the process works by running each document through a variety of templates (explained below) that add and subtract information in order to create a document that contains all of the necessary information for the creation of the JSON indexes. These modified documents are then output into a temporary directory (which is removed at the end of the ANT build).</xd:p>
            <xd:p>The templates/passes are described below. Note, however, that since many of these templates contain rules that are contingent on the configuration options, the templates for clean, weigh, and contextualize are primarily default templates that are usually overriden or supplemented by the implementer.</xd:p>
            <xd:ul>
                <xd:li>
                    <xd:b>exclude</xd:b>: Determines whether or not the document  has any exclusions or if the document itself is excluded. Note that the document is only passed through the exclusion templates if exclusions have been defined in the configuration file.</xd:li>
                <xd:li><xd:b>clean</xd:b>: Removes unnecessary tagging (spans, et cetera) in order to reduce the file size if possible and adds staticSearch specific attributes for later processing.</xd:li>
                <xd:li><xd:b>weigh</xd:b>: Adds @data-ss-weight attributes to the elements specified in the configuration file. This allows for higher weighting of terms found in particular contexts.</xd:li>
                <xd:li><xd:b>contextualize</xd:b>: Adds @data-ss-context to the elements specified in the configuration file so that KWICS, if generated in the JSON file, are properly bounded by their containing elements.</xd:li>
                <xd:li><xd:b>tokenize</xd:b>: Tokenizes the file on word boundaries, wraps each word in a span element, and adds a @data-ss-stem for that term. This is the bulk of the process.</xd:li>
                <xd:li><xd:b>enumerate</xd:b>: A final pass on the tokenized document, which adds a position for each stem. This helps with ordering results.</xd:li>
            </xd:ul>
        </xd:desc>
    </xd:doc>

    <!--**************************************************************
       *                                                            *
       *                         Includes                           *
       *                                                            *
       **************************************************************-->    
    
    <xd:doc>
        <xd:desc>Include the configuration file, which is generated via <xd:a href="create_config_xsl.xsl">create_config_xsl.xsl</xd:a>. Note that the stemmer XSLT is included
        in the config.</xd:desc>
    </xd:doc>
    <xsl:include href="config.xsl"/>
    
    <xd:doc>
        <xd:desc>Include the global functions file.</xd:desc>
    </xd:doc>
    <xsl:include href="functions.xsl"/>
    
    
    <!--**************************************************************
       *                                                            *
       *                         Output                             *
       *                                                            *
       **************************************************************-->    
    
    <xd:doc>
        <xd:desc>Output method that specifies that the output HTML files are
        not indented (important to ensure that the output formatting does not
        unwittingly break the input formatting) and that the output is XML.</xd:desc>
    </xd:doc>
    <xsl:output indent="no" method="xml"/>
    
    
    
    <!--**************************************************************
       *                                                            *
       *                         Variables                          *
       *                                                            *
       **************************************************************-->  
    
    <xd:doc>
        <xd:desc>A simple regex to match (x)?htm(l)? document URIs.</xd:desc>
    </xd:doc>
    <xsl:variable name="docRegex">(.+)(\..?htm.?$)</xsl:variable>
    
    <xd:doc>
        <xd:desc>Various apostrophes for use in regexes.</xd:desc>
    </xd:doc>
    <xsl:variable name="curlyAposOpen">‘</xsl:variable>
    <xsl:variable name="curlyAposClose">’</xsl:variable>
    <xsl:variable name="straightSingleApos">'</xsl:variable>
    <xsl:variable name="curlyDoubleAposOpen">“</xsl:variable>
    <xsl:variable name="curlyDoubleAposClose">”</xsl:variable>
    <xsl:variable name="straightDoubleApos">"</xsl:variable>
    
    <xsl:variable name="allSingleApos" 
        select="($straightSingleApos, $curlyAposOpen, $curlyAposClose)"
        as="xs:string+"/>
    
    <xsl:variable name="allSingleAposCharClassRex" 
        select="'[' || string-join($allSingleApos) || ']'" 
        as="xs:string"/>
    
    <xsl:variable name="allDoubleApos" 
        select="($curlyDoubleAposClose, $curlyDoubleAposOpen, $straightDoubleApos)" 
        as="xs:string+"/>
    
    <xsl:variable name="allDoubleAposCharClassRex"
        select="'[' || string-join($allDoubleApos) || ']'"
        as="xs:string"/>
    
    
    <xsl:variable name="allApos" select="($allSingleApos, $allDoubleApos)" as="xs:string+"/>
    
    
     <xd:doc>
         <xd:desc>Regex to match words that are numeric with a decimal</xd:desc>
     </xd:doc>
    <xsl:variable name="numericWithDecimal">[<xsl:value-of select="string-join($allApos,'')"/>\d]+([\.,]?\d+)</xsl:variable>
    
    <xd:doc>
        <xd:desc>Regex to match alphanumeric words</xd:desc>
    </xd:doc>
    <xsl:variable name="alphanumeric">[\p{L}<xsl:value-of select="string-join($allApos,'')"/>]+</xsl:variable>
    
    <xd:doc>
        <xd:desc>Regex to match hyphenated words</xd:desc>
    </xd:doc>
    <xsl:variable name="hyphenatedWord">(<xsl:value-of select="$alphanumeric"/>-<xsl:value-of select="$alphanumeric"/>(-<xsl:value-of select="$alphanumeric"/>)*)</xsl:variable>
    
    
    <xd:doc>
        <xd:desc>All of the above word regexes, strung together to match all
        possible words.</xd:desc>
    </xd:doc>
    <xsl:variable name="tokenRegex">(<xsl:value-of select="string-join(($numericWithDecimal,$hyphenatedWord,$alphanumeric),'|')"/>)</xsl:variable>
    
    
    <xd:doc>
        <xd:desc>Special document metadata classes that must have a name and class match</xd:desc>
    </xd:doc>
    <xsl:variable name="docMetas" select="('docTitle', 'docSortKey','docImage')" as="xs:string+"/>
    
    <!--TODO: Consider harmonizing these into a single variable or map-->
    
    <xd:doc>
        <xd:desc>Map of all of the descriptive filters found in the *entire* document
        collection. This is necessary so that each descriptive filter gets a unique id.</xd:desc>
    </xd:doc>  
    <xsl:variable name="descFilterMap" as="map(xs:string,xs:string)">
        <xsl:map>
            <xsl:for-each-group select="$docs//meta[contains-token(@class,'staticSearch.desc')]" group-by="@name">
                <xsl:map-entry key="xs:string(current-grouping-key())" select="'ssDesc' || position()"/>
            </xsl:for-each-group>
        </xsl:map>
    </xsl:variable>
    
    
    <xd:doc>
        <xd:desc>Map of all of the date filters found in the *entire* document
            collection. This is necessary so that each date filter gets a unique id.</xd:desc>
    </xd:doc>  
    <xsl:variable name="dateFilterMap" as="map(xs:string,xs:string)">
        <xsl:map>
            <xsl:for-each-group select="$docs//meta[contains-token(@class,'staticSearch.date')]" group-by="@name">
                <xsl:map-entry key="xs:string(current-grouping-key())" select="'ssDate' || position()"/>
            </xsl:for-each-group>
        </xsl:map>
    </xsl:variable>
    
    <xd:doc>
        <xd:desc>Map of all of the boolean filters found in the *entire* document
            collection. This is necessary so that each boolean filter gets a unique id.</xd:desc>
    </xd:doc>  
    <xsl:variable name="boolFilterMap" as="map(xs:string,xs:string)">
        <xsl:map>
            <xsl:for-each-group select="$docs//meta[contains-token(@class,'staticSearch.bool')]" group-by="@name">
                <xsl:map-entry key="xs:string(current-grouping-key())" select="'ssBool' || position()"/>
            </xsl:for-each-group>
        </xsl:map>
    </xsl:variable>
    
    
    <xd:doc>
        <xd:desc>Map of all of the numeric filters found in the *entire* document
            collection. This is necessary so that each numeric filter gets a unique id.</xd:desc>
    </xd:doc>  
  <xsl:variable name="numFilterMap" as="map(xs:string, xs:string)">
      <xsl:map>
          <xsl:for-each-group select="$docs//meta[contains-token(@class,'staticSearch.num')]" group-by="@name">
              <xsl:map-entry key="xs:string(current-grouping-key())" select="'ssNum' || position()"/>
          </xsl:for-each-group>
      </xsl:map>
  </xsl:variable>
    
    
    
    <!--**************************************************************
       *                                                            *
       *                         Root template                      *
       *                                                            *
       **************************************************************-->  
    
    
    <xd:doc>
        <xd:desc>Root/driver template.</xd:desc>
    </xd:doc>
    <xsl:template match="/">
        
        <!--Count the documents-->
        <xsl:variable name="count" select="count($docs)"/>
        
        <!--Output message for how many documents found-->
        <xsl:message>Found <xsl:value-of select="$count"/> documents to process...</xsl:message>
        
        <!--Call the "echoParams" template in the config file,
            which just outputs all parameters when verbose is true-->
        <xsl:call-template name="echoParams"/>
        
        <!--Now iterate through all of the documents-->
        <xsl:for-each select="$docs">
            
            <!--Get the document's position in the loop-->
            <xsl:variable name="pos" select="position()"/>
            <!--First, get the URI-->
            <xsl:variable name="uri" select="xs:string(document-uri(.))" as="xs:string"/>
            
            <!--Now find the relative uri from the root:
            this is the full URI minus the collection dir.
            
            Note that we TRIM off the leading slash since it does the root of the server.-->
            <xsl:variable name="relativeUri" 
                select="substring-after($uri,$collectionDir) => replace('^(/|\\)','')"
                as="xs:string"/>
            
            <!--This is the IDENTIFIER for the static search, which is just the relative URI with all of the punctuation/
             slashes et cetera that could conceivably be in filenames turned into underscores.
            --> 
            <xsl:variable name="searchIdentifier"
                select="replace($relativeUri,'^(/|\\)','') => 
                replace('\.x?html?$','') => 
                replace('\s+|\\|/|\.','_')" 
                as="xs:string"/>

            <!--Now create the various documents, and we put the leading slash BACK in-->
            <xsl:variable name="cleanedOutDoc"
                select="concat($tempDir,'/', $searchIdentifier,'_cleaned.html')"/>
            <xsl:variable name="contextualizedOutDoc"
                select="concat($tempDir,'/',$searchIdentifier,'_contextualized.html')"/>
            <xsl:variable name="weightedOutDoc"
                select="concat($tempDir,'/',$searchIdentifier,'_weighted.html')"/>
            <xsl:variable name="tokenizedOutDoc"
                select="concat($tempDir,'/',$searchIdentifier,'_tokenized.html')"/>
            <xsl:variable name="excludedOutDoc" 
                select="concat($tempDir,'/',$searchIdentifier,'_excluded.html')"/>
   
           
           <!--Now create the excluded document if we have to-->
           <xsl:variable name="excluded">
               <xsl:choose>
                   <!--If the exclusions are specified in the config, then run the document
                       through the exclusion templates (mode="exclude")-->
                   <xsl:when test="$hasExclusions">
                       <xsl:apply-templates mode="exclude"/>
                   </xsl:when>
                   
                   <!--Otherwise, just spit the document back out unchanged-->
                   <xsl:otherwise>
                       <xsl:sequence select="."/>
                   </xsl:otherwise>
               </xsl:choose>
           </xsl:variable>
            
            <!--Now check to see if exclusions are present in the configuration and if 
                the html root element has been specified as an exclusion. If the document is excluded,
                then just skip it from being indexed entirely. Otherwise, pass it through the process-->
            <xsl:if test="if ($hasExclusions) then not($excluded//html[@data-staticSearch-exclude='true']) else true()">
                
                <!--Output message to the user as to where we're at in the process-->
                <xsl:message>Tokenizing <xsl:value-of select="$uri"/> (<xsl:value-of select="$pos"/>/<xsl:value-of select="$count"/>)</xsl:message>
                
                <!--First, clean the document by passing it through the clean templates. This also
                    requires the relativeUri and searchIdentifier parameters in order to create
                    specific attributes that make the JSON creation simpler-->
                <xsl:variable name="cleaned">
                    <xsl:apply-templates select="$excluded" mode="clean">
                        <xsl:with-param name="relativeUri" select="$relativeUri" tunnel="yes"/>
                        <xsl:with-param name="searchIdentifier" select="$searchIdentifier" tunnel="yes"/>
                    </xsl:apply-templates>
                </xsl:variable>
                
                
                <!--Next add weighting information to the cleaned document-->
                <xsl:variable name="weighted">
                    <xsl:apply-templates select="$cleaned" mode="weigh"/>
                </xsl:variable>
                
                <!--Next add context information to the weighted document-->
                <xsl:variable name="contextualized">
                    <xsl:apply-templates select="$weighted" mode="contextualize"/>
                </xsl:variable>
                
                <!--Now create the tokenized document-->
                <xsl:result-document href="{$tokenizedOutDoc}">
                    
                    <!--If we're in verbose mode, then say what we're doing-->
                    <xsl:if test="$verbose">
                        <xsl:message>Creating <xsl:value-of select="$tokenizedOutDoc"/></xsl:message>
                    </xsl:if>
                    
                    <!--Next tokenize and stem the contextualized document-->
                    <xsl:variable name="tokenizedDoc">
                        <xsl:apply-templates select="$contextualized" mode="tokenize">
                            <xsl:with-param name="currDocUri" select="$uri" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:variable>
                    
                    <!--And finally pass the tokenized document through the enumeration templates-->
                    <xsl:apply-templates select="$tokenizedDoc" mode="enumerate"/>
                </xsl:result-document>
         
            
                <!--If we're running in verbose mode, then output all of the interstitial
                    documents for easier debugging.-->
                <xsl:if test="$verbose">
                    <xsl:message>Creating <xsl:value-of select="$cleanedOutDoc"/></xsl:message>
                    <xsl:result-document href="{$cleanedOutDoc}">
                        <xsl:copy-of select="$cleaned"/>
                    </xsl:result-document>
                    <xsl:message>Creating <xsl:value-of select="$contextualizedOutDoc"/></xsl:message>
                    <xsl:result-document href="{$contextualizedOutDoc}">
                        <xsl:copy-of select="$contextualized"/>
                    </xsl:result-document>
                    <xsl:message>Creating <xsl:value-of select="$weightedOutDoc"/></xsl:message>
                    <xsl:result-document href="{$weightedOutDoc}">
                        <xsl:copy-of select="$weighted"/>
                    </xsl:result-document>
                    <xsl:message>Creating <xsl:value-of select="$excludedOutDoc"/></xsl:message>
                    <xsl:result-document href="{$excludedOutDoc}">
                        <xsl:copy-of select="$excluded"/>
                    </xsl:result-document>
                </xsl:if>
            </xsl:if>
        </xsl:for-each>
    </xsl:template>
    
    
    <!--**************************************************************
       *                                                            *
       *                    Templates: clean                        *
       *                                                            *
       **************************************************************-->  
    
    
    <xd:doc>
        <xd:desc>This template matches the root HTML element with some parameters
            calculated from before for adding some identifying attributes</xd:desc>
        <xd:param name="relativeUri">The relative URI calculated by the root template.</xd:param>
        <xd:param name="searchIdentifier">The search identifier calculated by the root template.</xd:param>
    </xd:doc>
    <xsl:template match="html" mode="clean">
        <xsl:param name="relativeUri" tunnel="yes" as="xs:string"/>
        <xsl:param name="searchIdentifier" tunnel="yes" as="xs:string"/>
        <xsl:copy>
            <!--Apply templates to all of the attributes on the HTML element
                EXCEPT the id, which we might just duplicate or we might fill in-->
            <xsl:apply-templates select="@*[not(local-name()='id')]" mode="#current"/>
            
            <!--Now (potentially re-)make the id, either using the declared value
                or an inserted value-->
            <xsl:attribute name="id" select="if (@id) then @id else $searchIdentifier"/>
            <xsl:if test="not(@id)">
                <xsl:attribute name="data-staticSearch-noId" select="'true'"/>
            </xsl:if>
            
            <!--And create a relativeUri in the attribute, so we know where to point
                things if ids and filenames don't match or if nesting-->
            <xsl:attribute name="data-staticSearch-relativeUri" select="$relativeUri"/>
            
            <!--And process nodes normally-->
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    

    <xd:doc>
        <xd:desc>Basic template to strip away extraneous tags around elements that won't affect indexing in any way.
        Note that this template is overriden by templates in the configuration file if they have been specified
        as important for weighting or contextualizing.</xd:desc>
    </xd:doc>
    <xsl:template match="span | em | b | i | a" mode="clean">
        <xsl:if test="$verbose">
            <xsl:message>TEMPLATE clean: Matching <xsl:value-of select="local-name()"/></xsl:message>
        </xsl:if>
        <!--Just apply templates to the inner nodes-->
        <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template to convert all self closing elements--except for the wbr element (processed below)--into
            single spaces since we assume that they are word boundary marking</xd:desc>
    </xd:doc>
    <xsl:template match="br | hr | area | base | col | embed | hr | img | input | link[ancestor::body] | meta[ancestor::body] | param | source | track" mode="clean">
        <xsl:text> </xsl:text>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template that simply deletes the word break opportunity (wbr) element,
            since it is specifically not word breaking.</xd:desc>
    </xd:doc>
    <xsl:template match="wbr" mode="clean"/>
    
    <xd:doc>
        <xd:desc>Template to delete script elements in the body, since they
            will never contain information that should be indexed.</xd:desc>
    </xd:doc>
    <xsl:template match="script" mode="clean"/>
    
    
    <xd:doc>
        <xd:desc>Template to retain all elements that have a declared language, a declared id, or a
            special data-ss- attribute since we may need those elements in other contexts.</xd:desc>
    </xd:doc>
    <xsl:template match="*[@lang or @xml:lang or @id or @*[matches(local-name(),'^data-ss-')]][ancestor::body]" mode="clean">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    
    <!--**************************************************************
       *                                                            *
       *                    Templates: weigh                        *
       *                                                            *
       **************************************************************--> 
    
    <xd:doc>
        <xd:desc>Default weighting template that specifies that all headings have a weight
        of 2. Note that the other weighting templates are contained within the 
        generated configuration file and will override this one, if necessary.</xd:desc>
    </xd:doc>
    <xsl:template match="*[matches(local-name(),'^h\d$')]" mode="weigh">
        <xsl:copy>
            <xsl:apply-templates select="@*" mode="#current"/>
            <xsl:attribute name="data-staticSearch-weight" select="2"/>
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    

    
    <!--**************************************************************
       *                                                            *
       *                    Templates: contextualize                *
       *                                                            *
       **************************************************************-->  
    
    <xd:doc>
        <xd:desc>Template to match all block-like elements that we assume are contexts by default.</xd:desc>
    </xd:doc>
    <xsl:template match="body | div | blockquote | p | li | section | article | nav | h1 | h2 | h3 | h4 | h5 | h6 | td | details | summary" mode="contextualize">
        <xsl:copy>
            <xsl:apply-templates select="@*" mode="#current"/>
            <!--Add the data-staticSearch-context attribute-->
            <xsl:attribute name="data-staticSearch-context" select="'true'"/>
            <xsl:apply-templates select="node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template to remove all unnecessary attributes from the document to make
        processing more efficient; since the contextualization step is the final step
        before tokenizing, most of the elements attributes are unimportant by this point
        since any configuration based off of these attributes has already been handled
        by a previous template pass.</xd:desc>
    </xd:doc>
    <xsl:template match="*[not(self::meta)]/@*" mode="contextualize">
        <xsl:choose>
            <xsl:when test="local-name()=('id','lang')">
                <xsl:copy-of select="."/>
            </xsl:when>
            <xsl:when test="matches(local-name(),'^data-(staticSearch|ss)-')">
                <xsl:copy-of select="."/>
            </xsl:when>
            <xsl:otherwise/>
        </xsl:choose>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Checks docImage, docTitle, and docSortKey metas to make sure that they have matching values. </xd:desc>
    </xd:doc>
    <xsl:template match="meta[@name or @class][not(@data-staticSearch-exclude)]" mode="contextualize">
        <xsl:variable name="currMeta" select="."/>
        <!--Process the meta no matter what-->
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
        <!--But check to see if it's a candidate for checking--> 
        <xsl:if test="($currMeta/@name = $docMetas) or (some $meta in $docMetas satisfies matches($currMeta/@class, $meta))">
            <!--Iterate through them all in case there's a name/class mixup (i.e. docTitle with class staticSearch.docSortKey or something)-->
            <xsl:for-each select="$docMetas">
                <xsl:variable name="thisDocMeta" select="." as="xs:string"/>
                <xsl:variable name="thisDocMetaClass" select="'staticSearch.' || $thisDocMeta" as="xs:string"/>
                <xsl:variable name="hasName" select="exists($currMeta[@name = $thisDocMeta])" as="xs:boolean"/>
                <xsl:variable name="hasClass" select="exists($currMeta[contains-token(@class, $thisDocMetaClass)])" as="xs:boolean"/>
                <!--Has the name or a class, but not both, raise a warning.-->
                <xsl:if test="($hasName or $hasClass) and not($hasName and $hasClass)">
                    <xsl:message>WARNING: Bad meta tag in <xsl:value-of select="$currMeta/ancestor::html/@data-staticSearch-relativeUri"/> (<xsl:value-of select="'name: ' || $currMeta/@name || '; class=' || $currMeta/@class"/>). All <xsl:value-of select="$thisDocMeta"/> meta tags must have matching @name="<xsl:value-of select="$thisDocMeta"/>" and @class="<xsl:value-of select="$thisDocMetaClass"/>".</xsl:message>
                </xsl:if>
            </xsl:for-each>
        </xsl:if>
    </xsl:template>
    


    <!--**************************************************************
       *                                                            *
       *                    Templates: tokenize                     *
       *                                                            *
       **************************************************************--> 
    
    
    <!--TODO: Consider harmonizing these into a single template or a function of some sort-->
    <xd:doc>
        <xd:desc>Template that matches the staticSearch desc meta and assigns it an id based off of the descFilterMap.</xd:desc>
    </xd:doc>
    <xsl:template match="meta[contains-token(@class,'staticSearch.desc')][not(@data-staticSearch-exclude)]" mode="tokenize">
        <xsl:copy>
            <xsl:attribute name="data-staticSearch-filter-id" select="$descFilterMap(normalize-space(@name))"/>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template that matches the staticSearch date meta and assigns it an id based off of the dateFilterMap.</xd:desc>
    </xd:doc>
    <xsl:template match="meta[contains-token(@class,'staticSearch.date')][not(@data-staticSearch-exclude)]" mode="tokenize">
        <xsl:copy>
            <xsl:attribute name="data-staticSearch-filter-id" select="$dateFilterMap(normalize-space(@name))"/>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template that matches the staticSearch bool meta and assigns it an id based off of the boolFilterMap.</xd:desc>
    </xd:doc>
    <xsl:template match="meta[contains-token(@class,'staticSearch.bool')][not(@data-staticSearch-exclude)]" mode="tokenize">
        <xsl:copy>
            <xsl:attribute name="data-staticSearch-filter-id" select="$boolFilterMap(normalize-space(@name))"/>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    <xd:doc>
        <xd:desc>Template that matches the staticSearch num meta and assigns it an id based off of the numFilterMap.</xd:desc>
    </xd:doc>
    <xsl:template match="meta[contains-token(@class,'staticSearch.num')][not(@data-staticSearch-exclude)]" mode="tokenize">
        <xsl:copy>
            <xsl:attribute name="data-staticSearch-filter-id" select="$numFilterMap(normalize-space(@name))"/>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    
    <xd:doc>
        <xd:desc>Matches the staticSearch.docImage URL so that the URL is relative to the search file, not the containing document.</xd:desc>
        <xd:param name="currDocUri">Tunnelled parameter for the current document's URI, which we need to 
            pass in as a parameter since the document has been removed from its context.</xd:param>
    </xd:doc>
    <xsl:template match="meta[contains-token(@class,'staticSearch.docImage')]/@content[not(matches(.,'^https?'))]" mode="tokenize">
        <xsl:param name="currDocUri" as="xs:string" tunnel="yes"/>
        <xsl:variable name="absPath" as="xs:string" select="resolve-uri(., $currDocUri)"/>
        <xsl:variable name="newRelPath" as="xs:string" select="hcmc:makeRelativeUri($searchFile, $absPath)"/>
        <xsl:attribute name="content" select="$newRelPath"/>
    </xsl:template>
    
    
    
     <xd:doc>
         <xd:desc>Main tokenizing template: Match all text nodes that:
          * Are contained within the body element
          * Are not entirely whitespace
          * Are not descendant of an excluded element.
         </xd:desc>
     </xd:doc>
    <xsl:template match="text()[ancestor::body][not(matches(.,'^\s+$'))][not(ancestor::*[@data-staticSearch-exclude])]" mode="tokenize">
        
        <!--Stash the current node so that we can retain its context in later steps-->
        <xsl:variable name="currNode" select="."/>
        
        <!--Analyze the string and find all things we consider tokens-->
        <xsl:analyze-string select="." regex="{$tokenRegex}">
            <xsl:matching-substring>
                <!--If we've found a token, start the stemming process!-->
                <xsl:copy-of select="hcmc:startStemmingProcess(.)"/>
            </xsl:matching-substring>
            <xsl:non-matching-substring>
                <!--Otherwise, just return the string-->
                <xsl:value-of select="."/>
            </xsl:non-matching-substring>
        </xsl:analyze-string>
    </xsl:template>


    <xd:doc>
        <xd:desc><xd:ref name="hcmc:startStemmingProcessing">hcmc:startStemmingProcess</xd:ref> determines whether
        or not the token should be indexed based off a set of rules as described in hcmc:shouldIndex, and processes
        it if it should be. Since this is deterministic, we set @new-each-time to no.</xd:desc>
        <xd:param name="word">The input word token.</xd:param>
        <xd:return>One or more items: this could be a span, a text node, or a string.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:startStemmingProcess" new-each-time="no" as="item()+">
        <xsl:param name="word" as="xs:string"/>
        
        <!--If we're in verbose mode, then return the word-->
        <xsl:if test="$verbose">
            <xsl:message>$word: <xsl:value-of select="$word"/></xsl:message>
        </xsl:if>
        
        <!--Clean the word for stemming-->
        <xsl:variable name="wordToStem" select="hcmc:cleanWordForStemming($word)"/>
        <xsl:if test="$verbose">
            <xsl:message>$wordToStem: <xsl:value-of select="$wordToStem"/></xsl:message>
        </xsl:if>
        
        <!--Return it as a lowercase word-->
        <xsl:variable name="lcWord" select="lower-case($wordToStem)"/>
        <xsl:if test="$verbose">
            <xsl:message>$lcWord: <xsl:value-of select="$lcWord"/></xsl:message>
        </xsl:if>
        
        <!--Determine whether or not it should be indexed-->
        <xsl:variable name="shouldIndex" select="hcmc:shouldIndex($lcWord)"/>
        <xsl:if test="$verbose">
            <xsl:message>$shouldIndex: <xsl:value-of select="$shouldIndex"/></xsl:message>
        </xsl:if>
        
        <xsl:choose>
            <!--If it should, then create the stem for it-->
            <xsl:when test="$shouldIndex">
                <xsl:copy-of select="hcmc:getStem($word)"/>
            </xsl:when>
            
            <!--Otherwise, return the word as text-->
            <xsl:otherwise>
                <xsl:value-of select="$word"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    
  

    <xd:doc>
        <xd:desc><xd:ref name="hcmc:getStem">hcmc:getStem</xd:ref> takes the the word string and creates
        a span element with a set of attributes for use by the JSON indexing process.</xd:desc>
        <xd:param name="word">The *original* word to stem.</xd:param>
        <xd:return>A span element, furnished with a variety of attributes for use in the indexing process, that contains the original word.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:getStem" as="element(span)">
        <xsl:param name="word" as="xs:string"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $word: <xsl:value-of select="$word"/></xsl:message>
        </xsl:if>
        
        <!--Get the cleaned word again, since we're using the ORIGINAL word here, not the cleaned word
        we used to determine the word's stemmability in hcmc:startStemmingProcess -->
        <xsl:variable name="cleanedWord" select="hcmc:cleanWordForStemming($word)" as="xs:string"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $cleanedWord: <xsl:value-of select="$cleanedWord"/></xsl:message>
        </xsl:if>
        
        <!--Make it lowercase-->
        <xsl:variable name="lcWord" select="lower-case($cleanedWord)" as="xs:string"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $lcWord: <xsl:value-of select="$lcWord"/></xsl:message>
        </xsl:if>
        
        <!--Determine whether or not the word has a digit in it; if it does, then the word shouldn't be put
        through the stemmer-->
        <xsl:variable name="containsDigit" select="matches($cleanedWord,'\d+')" as="xs:boolean"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $containsDigit: <xsl:value-of select="$containsDigit"/></xsl:message>
        </xsl:if>
        
        <!--Check whether or not the word is in the dictionary-->
        <xsl:variable name="inDictionary" select="exists(key('w',$lcWord, $dictionaryFileXml))" as="xs:boolean"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $inDictionary: <xsl:value-of select="$inDictionary"/></xsl:message>
        </xsl:if>
        
        <!--Check whether or not the word is hyphenated-->
        <xsl:variable name="hyphenated" select="matches($word,'[A-Za-z]-[A-Za-z]')" as="xs:boolean"/>
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: hyphenated: <xsl:value-of select="$hyphenated"/></xsl:message>
        </xsl:if>

        
        <!--Now create the stem val-->
        <xsl:variable name="stemVal" 
            select="if ($containsDigit) then $lcWord else ss:stem($lcWord)"
            as="xs:string?"/>
        
        <xsl:if test="$verbose">
            <xsl:message>hcmc:getStem: $stemVal: <xsl:value-of select="$stemVal"/></xsl:message>
        </xsl:if>
        
        <!--Now do stuff-->
        <!--Wrap it in a span-->
                <span>
                    <xsl:if test="not(empty($stemVal))">
                        <xsl:attribute name="data-staticSearch-stem" select="$stemVal"/>
                    </xsl:if>
                    
                    <!--Fork again, in case we have a hyphenated construct-->
                    <xsl:choose>
                        
                        <!--When we have a hyphenated word, we want to split it into pieces-->
                        <xsl:when test="$hyphenated">
                            <xsl:if test="$verbose">
                                <xsl:message>hcmc:getStem: Found hyphenated construct: <xsl:value-of select="$word"/></xsl:message>
                            </xsl:if>
                            
                            <!--Split the word on the hyphens-->
                            <xsl:variable name="wordTokens" select="tokenize($word,'-')" as="xs:string+"/>
                            
                            <!--Now iterate through the hyphens-->
                            <xsl:for-each select="$wordTokens">
                                <xsl:variable name="thisToken" select="." as="xs:string"/>
                                <xsl:variable name="thisTokenPosition" select="position()"/>
                                
                                <!--Spit out a message if we want it-->
                                <xsl:if test="$verbose">
                                    <xsl:message>hcmc:getStem: Process hyphenated segment: <xsl:value-of select="$thisToken"/> (<xsl:value-of select="$thisTokenPosition"/>/<xsl:value-of select="count($wordTokens)"/>)</xsl:message>
                                </xsl:if>
                                
                                <!--Now run each hyphen through the process again, and add hyphens after each word-->
                                <xsl:sequence select="hcmc:startStemmingProcess(.)"/><xsl:if test="$thisTokenPosition ne count($wordTokens)"><xsl:text>-</xsl:text></xsl:if>
                            </xsl:for-each>
                        </xsl:when>
                       
                        <!--If it's not hyphenated, then just plop the content back in-->
                        <xsl:otherwise>
                            <xsl:value-of select="$word"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </span>
    </xsl:function>
    
    
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:cleanWordForStemming">hcmc:cleanWordForStemming</xd:ref> takes the input word
            and tidies it up to make it more amenable for the stemming process.</xd:desc>
        <xd:param name="word">The input word</xd:param>
        <xd:return>A cleaned version of the word.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:cleanWordForStemming" as="xs:string">
        <xsl:param name="word" as="xs:string"/>
        
        <xsl:value-of select="
            replace($word, $allDoubleAposCharClassRex, '') (: Remove all quotation marks :)
            => replace($allSingleAposCharClassRex, $straightSingleApos) (: Normalize all apostrophes to straight :)
            => replace('\.$','') (: Remove trailing period :)
            => replace('^' || $straightSingleApos, '') (: Remove leading apostrope :)
            => replace($straightSingleApos || '$', '') (: Remove trailing apostrophe :)
            => translate('ſ','s') (: Normalize long-s to regular s :)
            "/>
    </xsl:function>
    
    <xd:doc>
        <xd:desc><xd:ref name="hcmc:shouldIndex">hcmc:shouldIndex</xd:ref> returns a boolean value 
            regarding whether or not the word should be indexed. Currently the two conditions are:
            * The word must be longer than 2 letters
            * The word must not be a stopword</xd:desc>
        <xd:param name="lcWord">A lower-cased word.</xd:param>
        <xd:return>A boolean value.</xd:return>
    </xd:doc>
    <xsl:function name="hcmc:shouldIndex" as="xs:boolean">
        <xsl:param name="lcWord" as="xs:string"/>
        <xsl:sequence select="string-length($lcWord) gt 2 and not(key('w', $lcWord, $stopwordsFileXml))"/>
    </xsl:function>


    <!--**************************************************************
       *                                                            *
       *                    Templates: enumerate                    *
       *                                                            *
       **************************************************************--> 
    
    <xd:doc>
        <xd:desc>An accumulator that matches all generated spans so that we can get its position
        in the indexing phase</xd:desc>
    </xd:doc>
    <xsl:accumulator name="stem-position" initial-value="0">
        <xsl:accumulator-rule match="span[@data-staticSearch-stem]">
            <xsl:value-of select="$value + 1"/>
        </xsl:accumulator-rule>
    </xsl:accumulator>
    
    <xd:doc>
        <xd:desc>Accumulator that keeps track of the last processed id, which is helpful in instances where something
            may not have an ancestor id.</xd:desc>
    </xd:doc>
    <xsl:accumulator name="fragment-id" initial-value="()">
        <xsl:accumulator-rule match="*[@id][ancestor::body]"
            select="string(@id)"/>
    </xsl:accumulator>
    
    
    <xd:doc>
        <xd:desc>Template to match all ancestor ids</xd:desc>
    </xd:doc>
    <xsl:template match="*[@id][ancestor::body]" mode="enumerate">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current">
                <xsl:with-param name="id" select="string(@id)" tunnel="yes"/>
            </xsl:apply-templates>
        </xsl:copy>
    </xsl:template>
    
    
    <xd:doc>
        <xd:desc>Template to determine whether or not we can remove the @data-staticSearch-context from this
        element: if this element has other contexts declared, then we check to see if this element
        has any spans that need this context; if not, then we can delete the attribute since its superfluous.</xd:desc>
    </xd:doc>
    <xsl:template match="*[@data-staticSearch-context][descendant::*[@data-staticSearch-context]]/@data-staticSearch-context" mode="enumerate">
        <xsl:variable name="parent" select="parent::*" as="element()"/>
        <xsl:variable name="spans" select="$parent/descendant::span[@data-staticSearch-stem]" as="element(span)*"/>
        <!--If some span uses this element as its context ancestor, then we retain the attribute-->
        <xsl:if test="some $span in $spans satisfies $span/ancestor::*[@data-staticSearch-context][1][. is $parent]">
            <xsl:sequence select="."/>
        </xsl:if>
    </xsl:template>
    
    
    <xd:doc>
        <xd:desc>Match all of the generated spans and add a position to the element so that we
        can simply determine their order in later processes.</xd:desc>
    </xd:doc>
    <xsl:template match="span[@data-staticSearch-stem]" mode="enumerate">
        <xsl:param name="id" as="xs:string?" tunnel="yes"/>
        <!--Get the fragment id: if there's a tunneled id parameter, then we want to use that,
                since it is from the stem's ancestor; if there isn't, then we use the nearest preceding id.-->
        <xsl:variable name="fragmentId"
            select="if ($id) then $id else accumulator-before('fragment-id')" 
            as="xs:string?"/>
        <xsl:copy>
            <xsl:attribute name="data-staticSearch-pos" select="accumulator-before('stem-position')"/>
            <xsl:if test="exists($fragmentId)">
                <xsl:if test="$verbose">
                    <xsl:message>Found fragment id: <xsl:value-of select="$fragmentId"/> (method: <xsl:value-of select="if ($fragmentId = $id) then 'ancestor' else 'accumulator'"/>)</xsl:message>
                </xsl:if>
                <xsl:attribute name="data-staticSearch-fid" select="$fragmentId"/>
            </xsl:if>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>
    
    
    <!--**************************************************************
       *                                                            *
       *               Template: identity transform                 *
       *                                                            *
       **************************************************************-->
 
   <xd:doc>
       <xd:desc>Ol' faithful identity transform</xd:desc>
   </xd:doc>
   <xsl:template match="@*|node()" mode="#all" priority="-1">
       <xsl:copy>
           <xsl:apply-templates select="@*|node()" mode="#current"/>
       </xsl:copy>
   </xsl:template>
    
</xsl:stylesheet>
