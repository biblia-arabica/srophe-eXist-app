xquery version "3.0";
(:~
 : Shared functions for search modules 
 :)
module namespace common="http://syriaca.org/common";
import module namespace global="http://syriaca.org/global" at "../lib/global.xqm";
import module namespace kwic="http://exist-db.org/xquery/kwic" at "resource:org/exist/xquery/lib/kwic.xql";
import module namespace functx="http://www.functx.com";
declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Cleans search parameters to replace bad/undesirable data in strings
 : @param-string parameter string to be cleaned
:)
declare function common:clean-string($string){
common:strip-chars($string)
(:
let $luceneParse := common:parse-lucene(common:strip-chars($string))
let $luceneXML := util:parse($luceneParse)
let $query := common:lucene2xml($luceneXML/node()) 
return $luceneXML
:)
};

declare function common:strip-chars($string){
let $query-string := $string
let $query-string := 
	   if (functx:number-of-matches($query-string, '"') mod 2) then 
	       replace($query-string, '"', ' ')
	   else $query-string   (:if there is an uneven number of quotation marks, delete all quotation marks.:)
let $query-string := 
	   if ((functx:number-of-matches($query-string, '\(') + functx:number-of-matches($query-string, '\)')) mod 2 eq 0) 
	   then $query-string
	   else translate($query-string, '()', ' ') (:if there is an uneven number of parentheses, delete all parentheses.:)
let $query-string := 
	   if ((functx:number-of-matches($query-string, '\[') + functx:number-of-matches($query-string, '\]')) mod 2 eq 0) 
	   then $query-string
	   else translate($query-string, '[]', ' ') (:if there is an uneven number of brackets, delete all brackets.:)
let $query-string := replace($string,"'","")	   
return 
    if(matches($query-string,"(^\*$)|(^\?$)")) then 'Invalid Search String, please try again.' (: Must enter some text with wildcard searches:)
    else replace(replace($query-string,'<|>|@',''), '(\.|\[|\]|\\|\||\-|\^|\$|\+|\{|\}|\(|\)|(/))','\\$1') (: Escape special characters. Fixes error, but does not return correct results on URIs see: http://viaf.org/viaf/sourceID/SRP|person_308 :)
};

declare function common:parse-lucene($string) {
  if (matches($string, '[^\\](\|{2}|&amp;{2}|!) ')) then
    let $rep := replace(replace(replace($string, '&amp;{2} ', 'AND '), '\|{2} ', 'OR '), '! ', 'NOT ')
    return common:parse-lucene($rep)
  else if (matches($string, '[^<](AND|OR|NOT) ')) then
    let $rep := replace($string, '(AND|OR|NOT) ', '<$1/>')
    return common:parse-lucene($rep)
  else if (matches($string, '(^|[^\w&#34;&#39;])\+[\w&#34;&#39;(]')) then   
    let $rep := replace($string, '(^|[^\w&#34;&#39;])\+([\w&#34;&#39;(])', '$1<AND type=_+_/>$2')
    return common:parse-lucene($rep)
  else if (matches($string, '(^|[^\w&#34;&#39;])-[\w&#34;&#39;(]')) then   
    let $rep := replace($string, '(^|[^\w&#34;&#39;])-([\w&#34;&#39;(])', '$1<NOT type=_-_/>$2')
    return common:parse-lucene($rep)
  else if (matches($string, '(^|[\W-[\\]]|>)\(.*?[^\\]\)(\^(\d+))?(<|\W|$)')) then   
    let $rep := 
      if (matches($string, '(^|\W|>)\(.*?\)(\^(\d+))(<|\W|$)')) then
        replace($string, '(^|\W|>)\((.*?)\)(\^(\d+))(<|\W|$)', '$1<bool boost=_$4_>$2</bool>$5')
      else 
        replace($string, '(^|\W|>)\((.*?)\)(<|\W|$)', '$1<bool>$2</bool>$3')
    return common:parse-lucene($rep)
  else if (matches($string, '(^|\W|>)(&#34;|&#39;).*?\2([~^]\d+)?(<|\W|$)')) then
    let $rep := 
      if (matches($string, '(^|\W|>)(&#34;|&#39;).*?\2([\^]\d+)?(<|\W|$)')) then 
        replace($string, '(^|\W|>)(&#34;|&#39;)(.*?)\2([~^](\d+))?(<|\W|$)', '$1<near boost=_$5_>$3</near>$6')
      else 
        replace($string, '(^|\W|>)(&#34;|&#39;)(.*?)\2([~^](\d+))?(<|\W|$)', '$1<near slop=_$5_>$3</near>$6')
    return common:parse-lucene($rep)
  else if (matches($string, '[\w-[<>]]+?~[\d.]*')) then
    let $rep := replace($string, '([\w-[<>]]+?)~([\d.]*)', '<fuzzy min-similarity=_$2_>$1</fuzzy>')
    return common:parse-lucene($rep)
  else concat('<query>', replace(normalize-space($string), '_', '"'), '</query>')
};

declare function common:lucene2xml($node) {
  typeswitch ($node)
    case element(query) return 
      element { node-name($node)} {
        element bool {
          $node/node()/common:lucene2xml(.)
        }
      }
    case element(AND) return ()
    case element(OR) return ()
    case element(NOT) return ()
    case element() return
      let $name := if (($node/self::phrase|$node/self::near)[not(@slop > 0)]) then 'phrase' else node-name($node)
      return 
        element { $name } {
          $node/@*,
          if (($node/following-sibling::*[1]|$node/preceding-sibling::*[1])[self::AND or self::OR or self::NOT]) then
            attribute occur { 
              if ($node/preceding-sibling::*[1][self::AND]) then 'must' 
              else if ($node/preceding-sibling::*[1][self::NOT]) then 'not'
              else if ($node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) then 'should' (:'must':)
              else 'should'
            }
          else (),
          $node/node()/common:lucene2xml(.)
        }
    case text() return 
      if ($node/parent::*[self::query or self::bool]) then
        for $tok at $p in tokenize($node, '\s+')[normalize-space()]
        (: here is the place for further differentiation between  term / wildcard / regex elements :)
        let $el-name := 
          if (matches($tok, '(^|[^\\])[$^|+\p{P}-[,]]')) then 
            if (matches($tok, '(^|[^\\.])[?*+]|\[!')) then 'wildcard'
            else 'regex' 
          else 'term'
        return element { $el-name } {
          attribute occur {
            if ($p = 1 and $node/preceding-sibling::*[1][self::AND]) then 'must'
            else if ($p = 1 and $node/preceding-sibling::*[1][self::NOT]) then 'not'
            else if ($p = 1 and $node/following-sibling::*[1][self::AND or self::OR or self::NOT][not(@type)]) then 'should' (:'must':)
            else 'should'
          },
          if (matches($tok, '(.*?)(\^(\d+))(\W|$)')) then
            attribute boost {
              replace($tok, '(.*?)(\^(\d+))(\W|$)', '$3')
            }
            else (),
          lower-case(normalize-space(replace($tok, '(.*?)(\^(\d+))(\W|$)', '$1')))
        }
      else 
        normalize-space($node)
  default return
    $node
};

(:~
 : Strips english titles of non-sort characters as established by Syriaca.org
 : Used for sorting for browse and search modules
 : @param $titlestring 
 :)
declare function common:build-sort-string($titlestring as xs:string*) as xs:string* {
    replace(replace(replace(replace($titlestring,'^\s+',''),'^al-',''),'[‘ʻʿ]',''),'On ','')
};

(:~
 : Search options passed to ft:query functions
:)
declare function common:options(){
    <options>
        <default-operator>and</default-operator>
        <phrase-slop>1</phrase-slop>
        <leading-wildcard>yes</leading-wildcard>
        <filter-rewrite>yes</filter-rewrite>
    </options>
};

(:~
 : Function to cast dates strings from url to xs:date
 : Tests string length, may need something more sophisticated to test dates, 
 : or form validation via js before submit. 
 : @param $date passed to function from parent function
:)
declare function common:do-date($date){
let $date-format := if(string-length($date) eq 4) then concat(string($date),'-01-01')
                    else if(string-length($date) eq 5) then concat(string($date),'-01-01')
                    else if(string-length($date) eq 3) then concat('0',string($date),'-01-01')
                    else if(string-length($date) eq 2) then concat('00',string($date),'-01-01')
                    else if(string-length($date) eq 1) then concat('000',string($date),'-01-01')
                    else string($date) 
return xs:date($date-format)
};

(:
 : Function to truncate description text after first 12 words
 : @param $string
:)
declare function common:truncate-string($str as xs:string*) as xs:string? {
let $string := string-join($str, ' ')
return 
    if(count(tokenize($string, '\W+')[. != '']) gt 12) then 
        let $last-words := tokenize($string, '\W+')[position() = 14]
        return concat(substring-before($string, $last-words),'...')
    else $string
};

declare function common:keyword($q){
    if(exists($q) and $q != '') then 
        concat("[ft:query(.,'",common:clean-string($q),"',common:options())]")
    else '' 
};

declare function common:element-search($element, $query){
    if(exists($element) and $element != '') then 
        for $e in $element
        return concat("[ft:query(descendant::tei:",$element,",'",common:clean-string($query),"',common:options())]") 
    else '' 
};