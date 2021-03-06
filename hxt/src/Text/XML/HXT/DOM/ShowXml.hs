-- ------------------------------------------------------------

{- |
   Module     : Text.XML.HXT.DOM.ShowXml
   Copyright  : Copyright (C) 2008-9 Uwe Schmidt
   License    : MIT

   Maintainer : Uwe Schmidt (uwe@fh-wedel.de)
   Stability  : stable
   Portability: portable

   XML tree conversion to external string representation

-}

-- ------------------------------------------------------------

module Text.XML.HXT.DOM.ShowXml
    ( xshow
    , showElemType
    )
where

import Data.Maybe
import Data.Tree.NTree.TypeDefs

import Text.XML.HXT.DOM.TypeDefs                -- XML Tree types
import Text.XML.HXT.DOM.XmlKeywords
import Text.XML.HXT.DOM.XmlNode                 ( mkDTDElem
                                                , getDTDAttrl
                                                )

-- -----------------------------------------------------------------------------
--
-- the toString conversion functions

-- |
-- convert the result of a filter into a string
--
-- see also : 'xmlTreesToText' for filter version, 'Text.XML.HXT.Parser.XmlParsec.xread' for the inverse operation

xshow   :: XmlTrees -> String
xshow [(NTree (XText s) _)]     = s                     -- special case optimisation
xshow ts                        = showXmlTrees ts ""

-- ------------------------------------------------------------

showXmlTree             :: XmlTree  -> String -> String

showXmlTree (NTree (XText s) _)
    = showString s

showXmlTree (NTree (XCharRef i) _)
    = showString "&#" . showString (show i) . showChar ';'

showXmlTree (NTree (XEntityRef r) _)
    = showString "&" . showString r . showChar ';'

showXmlTree (NTree (XCmt c) _)
    = showString "<!--" . showString c . showString "-->"

showXmlTree (NTree (XCdata d) _)
    = showString "<![CDATA[" . showString d . showString "]]>"

showXmlTree (NTree (XPi n al) _)
    = showString "<?"
      .
      showQName n
      .
      (foldr (.) id . map showPiAttr) al
      .
      showString "?>"
      where
      showPiAttr        :: XmlTree -> String -> String
      showPiAttr a@(NTree (XAttr an) cs)
          | qualifiedName an == a_value
              = showBlank . showXmlTrees cs
          | otherwise
              = showXmlTree a
      showPiAttr _
          = id

showXmlTree (NTree (XTag t al) [])
    = showLt . showQName t . showXmlTrees al . showSlash . showGt

showXmlTree (NTree (XTag t al) cs)
    = showLt . showQName t . showXmlTrees al . showGt
      . showXmlTrees cs
      . showLt . showSlash . showQName t . showGt

showXmlTree (NTree (XDTD de al) cs)
    = showXmlDTD de al cs

showXmlTree (NTree (XAttr an) cs)
    = showBlank . showQName an . showEq . showQuoteString (xshow cs)

showXmlTree (NTree (XError l e) _)
    = showString "<!-- ERROR (" . shows l . showString "):\n" . showString e . showString "\n-->"

-- ------------------------------------------------------------

showXmlTrees            :: XmlTrees -> String -> String
showXmlTrees            = foldr (.) id . map showXmlTree

showXmlTrees'           :: XmlTrees -> String -> String
showXmlTrees'           = foldr (\ x y -> x . showNL . y) id . map showXmlTree

-- ------------------------------------------------------------

showQName               :: QName -> String -> String
showQName
    = showString . qualifiedName

-- ------------------------------------------------------------

showQuoteString         :: String -> String -> String
showQuoteString s
    | '\"' `elem` s
        = showApos . showString s . showApos
    | otherwise
        = showQuot . showString s . showQuot


-- ------------------------------------------------------------

showAttr        :: String -> Attributes -> String -> String
showAttr k al
    = showString (fromMaybe "" . lookup k $ al)

-- ------------------------------------------------------------

showPEAttr      :: Attributes -> String -> String
showPEAttr al
    = showPE (lookup a_peref al)
      where
      showPE (Just pe) = showChar '%' . showString pe . showChar ';'
      showPE Nothing   = id

-- ------------------------------------------------------------

showExternalId  :: Attributes -> String -> String
showExternalId al
    = id2Str (lookup k_system al) (lookup k_public al)
      where
      id2Str Nothing  Nothing  = id
      id2Str (Just s) Nothing  = showBlank . showString k_system . showBlank . showQuoteString s
      id2Str Nothing  (Just p) = showBlank . showString k_public . showBlank . showQuoteString p
      id2Str (Just s) (Just p) = showBlank . showString k_public . showBlank . showQuoteString p . showBlank . showQuoteString s

-- ------------------------------------------------------------

showNData       :: Attributes -> String -> String
showNData al
    = nd2Str (lookup k_ndata al)
      where
      nd2Str Nothing    = id
      nd2Str (Just v)   = showBlank . showString k_ndata . showBlank . showString v

-- ------------------------------------------------------------

showXmlDTD              :: DTDElem -> Attributes -> XmlTrees -> String -> String

showXmlDTD DOCTYPE al cs
    = showString "<!DOCTYPE "
      .
      showAttr a_name al
      .
      showExternalId al
      .
      showInternalDTD cs
      .
      showString ">"
      where
      showInternalDTD [] = id
      showInternalDTD ds = showString " [\n" . showXmlTrees' ds . showChar ']'

showXmlDTD ELEMENT al cs
    = showString "<!ELEMENT "
      .
      showAttr a_name al
      .
      showBlank
      .
      showElemType (lookup1 a_type al) cs
      .
      showString " >"

showXmlDTD ATTLIST al cs
    = showString "<!ATTLIST "
      .
      ( if isNothing . lookup a_name $ al
        then
        showXmlTrees cs
        else
        showAttr a_name al
        .
        showBlank
        .
        ( case lookup a_value al of
          Nothing -> ( showPEAttr
                       . fromMaybe [] . getDTDAttrl
                       . head
                     ) cs
          Just a  -> ( showString a
                       .
                       showAttrType (lookup1 a_type al)
                       .
                       showAttrKind (lookup1 a_kind al)
                     )
        )
      )
      .
      showString " >"
      where
      showAttrType t
          | t == k_peref
              = showBlank . showPEAttr al
          | t == k_enumeration
              = showAttrEnum
          | t == k_notation
              = showBlank . showString k_notation . showAttrEnum
          | otherwise
              = showBlank . showString t

      showAttrEnum
          = showString " ("
            .
            foldr1 (\ s1 s2 -> s1 . showString " | " .  s2) (map (getEnum . fromMaybe [] . getDTDAttrl) cs)
            .
            showString ")"
            where
            getEnum     :: Attributes -> String -> String
            getEnum l = showAttr a_name l . showPEAttr l

      showAttrKind k
          | k == k_default
              = showBlank . showQuoteString (lookup1 a_default al)
          | k == k_fixed
              = showBlank . showString k_fixed
                .
                showBlank . showQuoteString (lookup1 a_default al)
          | k == ""
              = id
          | otherwise
              = showBlank . showString k

showXmlDTD NOTATION al _cs
    = showString "<!NOTATION "
      .
      showAttr a_name al
      .
      showExternalId al
      .
      showString " >"

showXmlDTD PENTITY al cs
    = showEntity "% " al cs

showXmlDTD ENTITY al cs
    = showEntity "" al cs

showXmlDTD PEREF al _cs
    = showPEAttr al

showXmlDTD CONDSECT _ (c1 : cs)
    = showString "<![ "
      .
      showXmlTree c1
      .
      showString " [\n"
      .
      showXmlTrees cs
      .
      showString "]]>"

showXmlDTD CONTENT al cs
    = showContent (mkDTDElem CONTENT al cs)

showXmlDTD NAME al _cs
    = showAttr a_name al

showXmlDTD de al _cs
    = showString "NOT YET IMPLEMETED: " . showString (show de) . showBlank . showString (show al) . showString " [...]\n"

-- ------------------------------------------------------------

showElemType    :: String -> XmlTrees -> String -> String
showElemType t cs
    | t == v_pcdata
        = showLpar . showString v_pcdata . showRpar

    | t == v_mixed && (not . null) cs
        = showLpar
          .
          showString v_pcdata
          .
          ( foldr (.) id . map (mixedContent . selAttrl . getNode) ) cs1
          .
          showRpar
          .
          showAttr a_modifier al1
    | t == v_mixed                              -- incorrect tree, e.g. after erronius pe substitution
        = showLpar
          .
          showRpar
    | t == v_children && (not . null) cs
        = showContent (head cs)
    | t == v_children
        = showLpar
          . showRpar
    | t == k_peref
        = foldr (.) id . map showContent $ cs
    | otherwise
        = showString t
    where
    [(NTree (XDTD CONTENT al1) cs1)] = cs

    mixedContent :: Attributes -> String -> String
    mixedContent l
        = showString " | " . showAttr a_name l . showPEAttr l

    selAttrl (XDTD _ as) = as
    selAttrl (XText tex) = [(a_name, tex)]
    selAttrl _           = []

-- ------------------------------------------------------------

showContent     :: XmlTree -> String -> String
showContent (NTree (XDTD de al) cs)
    = cont2String de
      where
      cont2String       :: DTDElem -> String -> String
      cont2String NAME
          = showAttr a_name al
      cont2String PEREF
          = showPEAttr al
      cont2String CONTENT
          = showLpar
            .
            foldr1 (combine (lookup1 a_kind al)) (map showContent cs)
            .
            showRpar
            .
            showAttr a_modifier al
      cont2String n
          = error ("cont2string " ++ show n ++ " is undefined")
      combine k s1 s2
          = s1
            .
            showString ( if k == v_seq
                         then ", "
                         else " | "
                       )
            .
            s2

showContent n
    = showXmlTree n

-- ------------------------------------------------------------

showEntity      :: String -> Attributes -> XmlTrees -> String -> String

showEntity kind al cs
    = showString "<!ENTITY "
      .
      showString kind
      .
      showAttr a_name al
      .
      showExternalId al
      .
      showNData al
      .
      showEntityValue cs
      .
      showString " >"

-- ------------------------------------------------------------

showEntityValue :: XmlTrees -> String -> String

showEntityValue []
    = id

showEntityValue cs
    = showBlank . showQuoteString (xshow cs)

-- ------------------------------------------------------------

showBlank,
  showEq, showLt, showGt, showSlash, showApos, showQuot, showLpar, showRpar, showNL :: String -> String

showBlank       = showChar ' '
showEq          = showChar '='
showLt          = showChar '<'
showGt          = showChar '>'
showSlash       = showChar '/'
showApos        = showChar '\''
showQuot        = showChar '\"'
showLpar        = showChar '('
showRpar        = showChar ')'
showNL          = showChar '\n'

-- -----------------------------------------------------------------------------
