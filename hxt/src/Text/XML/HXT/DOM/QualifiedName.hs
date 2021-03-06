{-# LANGUAGE DeriveDataTypeable #-}

-- ------------------------------------------------------------

{- |
   Module     : Text.XML.HXT.DOM.QualifiedName
   Copyright  : Copyright (C) 2008 Uwe Schmidt
   License    : MIT

   Maintainer : Uwe Schmidt (uwe@fh-wedel.de)
   Stability  : stable
   Portability: portable

   The core data types of the HXT DOM.

-}

-- ------------------------------------------------------------

module Text.XML.HXT.DOM.QualifiedName
    ( QName
    , XName
    , NsEnv

    , mkQName
    , mkName
    , mkNsName
    , mkSNsName
    , mkPrefixLocalPart

    , equivQName
    , equivUri
    , equalQNameBy

    , namePrefix
    , localPart
    , namespaceUri

    , newXName
    , nullXName
    , isNullXName

    , mkQName'
    , namePrefix'
    , localPart'
    , namespaceUri'

    , setNamePrefix'
    , setLocalPart'
    , setNamespaceUri'

    , qualifiedName
    , universalName
    , universalUri
    , buildUniversalName

    , normalizeNsUri

    , setNamespace                      -- namespace related functions
    , isNCName
    , isWellformedQualifiedName
    , isWellformedQName
    , isWellformedNSDecl
    , isWellformedNameSpaceName
    , isNameSpaceName
    , isDeclaredNamespace

    , xmlNamespaceXName
    , xmlXName
    , xmlnsNamespaceXName
    , xmlnsXName
    , xmlnsQN

    , toNsEnv
    )

where

{-
import           Debug.Trace
 -}

import           Control.Arrow                  ( (***) )

import           Control.Concurrent.MVar
import           Control.DeepSeq

import           Data.AssocList
import           Data.Binary
import           Data.Char                      ( toLower )
import           Data.List                      ( isPrefixOf )
import qualified Data.Map               as M
import           Data.Typeable

import           System.IO.Unsafe               ( unsafePerformIO )

import           Text.XML.HXT.DOM.XmlKeywords   ( a_xml
                                                , a_xmlns
                                                , xmlNamespace
                                                , xmlnsNamespace
                                                )

import Data.Char.Properties.XMLCharProps        ( isXmlNCNameStartChar
                                                , isXmlNCNameChar
                                                )

-- -----------------------------------------------------------------------------

-- | XML names are represented by Strings, but these strings do not mix up with normal strings.
-- Names are always reduced to normal form, and they are stored internally in a name cache
-- for sharing equal names by the same data structure

type XName      = Atom

-- |
-- Namespace support for element and attribute names.
--
-- A qualified name consists of a name prefix, a local name
-- and a namespace uri.
-- All modules, which are not namespace aware, use only the 'localPart' component.
-- When dealing with namespaces, the document tree must be processed by 'Text.XML.HXT.Arrow.Namespace.propagateNamespaces'
-- to split names of structure \"prefix:localPart\" and label the name with the apropriate namespace uri

data QName      = LP ! XName
                | PX ! XName ! QName
                | NS ! XName ! QName
             deriving (Ord, Show, Read, Typeable)

-- |
-- Type for the namespace association list, used when propagating namespaces by
-- modifying the 'QName' values in a tree

type NsEnv = AssocList XName XName

-- -----------------------------------------------------------------------------

-- | Two QNames are equal if (1. case) namespaces are both empty and the qualified names
-- (prefix:localpart) are the same or (2. case) namespaces are set and namespaces and
-- local parts both are equal

instance Eq QName where
    (LP lp1)     == (LP lp2)            = lp1 == lp2
    (PX px1 qn1) == (PX px2 qn2)        = px1 == px2 && qn1== qn2
    (NS ns1 qn1) == (NS ns2 qn2)        = ns1 == ns2 && localPart' qn1 == localPart' qn2
    n1@(PX _ _)  == n2@(LP _)           = qualifiedName n1 == qualifiedName n2
    n1@(LP _)    == n2@(PX _ _)         = qualifiedName n1 == qualifiedName n2
    _            == _                   = False

-- the 4. and 5. rule are only neccessary when someone
-- uses XML names not in a systematical way
-- and does things like "mkName("x:y") == mkPrefixLocalPart("x","y")

instance NFData QName where

instance Binary QName where
    put qn              = let
                          px = namePrefix   qn
                          lp = localPart    qn
                          ns = namespaceUri qn
                          in
                          put px >> put lp >> put ns
    get                 = do
                          px <- get
                          lp <- get
                          ns <- get
                          return $ mkQName px lp ns

-- -----------------------------------------------------------------------------

newXName                :: String -> XName
newXName                = newAtom

isNullXName             :: XName -> Bool
isNullXName             = (== nullXName)

nullXName               :: XName
nullXName               = newXName ""

-- | access name prefix

namePrefix'             :: QName -> XName
namePrefix' (LP _)      = nullXName
namePrefix' (PX px _)   = px
namePrefix' (NS _ n)    = namePrefix' n

-- | access local part

localPart'              :: QName -> XName
localPart' (LP lp)      = lp
localPart' (PX _ n)     = localPart' n
localPart' (NS _ n)     = localPart' n

-- | access namespace uri

namespaceUri'           :: QName -> XName
namespaceUri' (NS ns _) = ns
namespaceUri' _         = nullXName

namePrefix              :: QName -> String
namePrefix              = show . namePrefix'

localPart               :: QName -> String
localPart               = show . localPart'

namespaceUri            :: QName -> String
namespaceUri            = show . namespaceUri'

-- ------------------------------------------------------------

-- | set name prefix

setNamespaceUri'                :: XName -> QName -> QName
setNamespaceUri' ns (NS _ n)    = if isNullXName ns
                                  then n
                                  else NS ns n
setNamespaceUri' ns n           = if isNullXName ns
                                  then n
                                  else NS ns n

-- | set local part

setLocalPart'                   :: XName -> QName -> QName
setLocalPart' lp (LP _)         = LP lp
setLocalPart' lp (PX px n)      = PX px (setLocalPart' lp n)
setLocalPart' lp (NS ns n)      = NS ns (setLocalPart' lp n)

-- | set name prefix

setNamePrefix'                  :: XName -> QName -> QName
setNamePrefix' px (PX _ n)      = if px == nullXName
                                  then n
                                  else PX px n
setNamePrefix' px n@(LP _)      = if px == nullXName
                                  then n
                                  else PX px n
setNamePrefix' px (NS ns n)     = NS ns (setNamePrefix' px n)


-- ------------------------------------------------------------

-- |
-- builds the full name \"prefix:localPart\", if prefix is not null, else the local part is the result

qualifiedName                   :: QName -> String
qualifiedName (LP lp)           = show lp
qualifiedName (PX px n)         = show px ++ (':' : qualifiedName n)
qualifiedName (NS _ n)          = qualifiedName n

-- |
-- builds the \"universal\" name, that is the namespace uri surrounded with \"{\" and \"}\" followed by the local part
-- (specialisation of 'buildUniversalName')

universalName                   :: QName -> String
universalName                   = buildUniversalName (\ ns lp -> '{' : ns ++ '}' : lp)

-- |
-- builds an \"universal\" uri, that is the namespace uri followed by the local part. This is usefull for RDF applications,
-- where the subject, predicate and object often are concatenated from namespace uri and local part
-- (specialisation of 'buildUniversalName')

universalUri                    :: QName -> String
universalUri                    = buildUniversalName (++)

-- |
-- builds a string from the namespace uri and the local part. If the namespace uri is empty, the local part is returned, else
-- namespace uri and local part are combined with the combining function given by the first parameter

buildUniversalName              :: (String -> String -> String) -> QName -> String
buildUniversalName bf (NS ns n) = show ns `bf` localPart n
buildUniversalName _  n         = localPart n

-- ------------------------------------------------------------
--
-- internal XName functions

mkQName'                        :: XName -> XName -> XName -> QName
mkQName' px lp ns
    | isNullXName ns            =       px_lp
    | otherwise                 = NS ns px_lp
    where
    px_lp
        | isNullXName px        = LP lp
        | otherwise             = PX px (LP lp)

-- ------------------------------------------------------------

-- |
-- constructs a simple name, with prefix and localPart but without a namespace uri.
--
-- see also 'mkQName', 'mkName'

mkPrefixLocalPart               :: String -> String -> QName
mkPrefixLocalPart px lp
    | null px                   =                  n1
    | otherwise                 = PX (newXName px) n1
    where
    n1 = LP (newXName lp)

-- |
-- constructs a simple, namespace unaware name.
-- If the name is in @prefix:localpart@ form and the prefix is not empty
-- the name is split internally into
-- a prefix and a local part.

mkName                          :: String -> QName
mkName n
    | (':' `elem` n)
      &&
      not (null px)                     -- more restrictive: isWellformedQualifiedName n
                                = mkPrefixLocalPart px lp
    | otherwise                 = mkPrefixLocalPart "" n
    where
    (px, (_:lp)) = span (/= ':') n

-- |
-- constructs a complete qualified name with 'namePrefix', 'localPart' and 'namespaceUri'.
-- This function can be used to build not wellformed prefix:localpart names.
-- The XPath module uses wildcard names like @xxx:*@. These must be build with 'mkQName'
-- and not with mkName.

mkQName                         :: String -> String -> String -> QName
mkQName px lp ns
    | null ns                   =                  n1
    | otherwise                 = NS (newXName ns) n1
    where
    n1 = mkPrefixLocalPart px lp

-- ------------------------------------------------------------

-- |
-- old name for 'mkName'

mkSNsName                       :: String -> QName
mkSNsName                       = mkName

-- |
-- constructs a simple, namespace aware name, with prefix:localPart as first parameter,
-- namspace uri as second.
--
-- see also 'mkName', 'mkPrefixLocalPart'

mkNsName                        :: String -> String -> QName
mkNsName n ns
    | null ns                   =                   mkName n
    | otherwise                 = NS (newXName ns) (mkName n)

-- ------------------------------------------------------------

-- | Equivalent QNames are defined as follows: The URIs are normalized before comparison.
-- Comparison is done with 'equalQNameBy' and 'equivUri'

equivQName                      :: QName -> QName -> Bool
equivQName                      = equalQNameBy equivUri

-- | Comparison of normalized namespace URIs using 'normalizeNsUri'

equivUri                        :: String -> String -> Bool
equivUri x y                    = normalizeNsUri x == normalizeNsUri y

-- | Sometimes a weaker equality relation than 'equalQName' is appropriate, e.g no case significance in names, ...
-- a name normalization function can be applied to the strings before comparing. Called by 'equalQName' and
-- 'equivQName'

equalQNameBy                    :: (String -> String -> Bool) -> QName -> QName -> Bool
equalQNameBy equiv q1 q2        = localPart q1 == localPart q2
                                  &&
                                  (namespaceUri q1 `equiv` namespaceUri q2)

-- |  Normalization of URIs: Normalization is done by conversion into lowercase letters. A trailing \"\/\" is ignored

normalizeNsUri                  :: String -> String
normalizeNsUri                  = map toLower . stripSlash
    where
    stripSlash ""               = ""
    stripSlash s
        | last s == '/'         = init s
        | otherwise             = s

-- -----------------------------------------------------------------------------

-- Namespace predicates

-- |
-- Compute the name prefix and the namespace uri for a qualified name.
--
-- This function does not test whether the name is a wellformed qualified name.
-- see Namespaces in XML Rule [6] to [8]. Error checking is done with separate functions,
-- see 'isWellformedQName' and 'isWellformedQualifiedName' for error checking.

setNamespace                    :: NsEnv -> QName -> QName
setNamespace env n@(PX px _)    = attachNS env px        n              -- none empty prefix found
setNamespace env n@(LP _)       = attachNS env nullXName n              -- use default namespace uri
setNamespace env (NS _ n)       = setNamespace env n

attachNS                        :: NsEnv -> XName -> QName -> QName
attachNS env px n1              = maybe n1 (\ ns -> NS ns n1) . lookup px $ env

xmlnsNamespaceXName             :: XName
xmlnsNamespaceXName             = newXName xmlnsNamespace

xmlnsXName                      :: XName
xmlnsXName                      = newXName a_xmlns

xmlnsQN                         :: QName
xmlnsQN                         = NS xmlnsNamespaceXName (LP xmlnsXName)

xmlNamespaceXName               :: XName
xmlNamespaceXName               = newXName xmlNamespace

xmlXName                        :: XName
xmlXName                        = newXName a_xml

-- -----------------------------------------------------------------------------
--

-- |
-- test for wellformed NCName, rule [4] XML Namespaces

isNCName                        :: String -> Bool
isNCName []                     = False
isNCName n                      = and ( zipWith ($)
                                        (isXmlNCNameStartChar : repeat isXmlNCNameChar)
                                        n
                                      )

-- |
-- test for wellformed QName, rule [6] XML Namespaces
-- predicate is used in filter 'valdateNamespaces'.

isWellformedQualifiedName       :: String -> Bool
isWellformedQualifiedName s
    | null lp                   = isNCName px
    | otherwise                 = isNCName px && isNCName (tail lp)
    where
    (px, lp)                    = span (/= ':') s

-- |
-- test for wellformed QName values.
-- A QName is wellformed, if the local part is a NCName, the namePrefix, if not empty, is also a NCName.
-- predicate is used in filter 'valdateNamespaces'.

isWellformedQName               :: QName -> Bool
isWellformedQName (LP lp)       = isNCName . show $ lp                          -- rule [8] XML Namespaces
isWellformedQName (PX px n)     = (isNCName . show) px                          -- rule [7] XML Namespaces
                                  &&
                                  isWellformedQName n
isWellformedQName (NS _ n)      = isWellformedQName n

-- |
-- test whether an attribute name is a namesapce declaration name.
-- If this is not the case True is the result, else
-- the name must be a well formed namespace name:
-- All namespace prefixes starting with \"xml\" are reserved for XML related definitions.
-- predicate is used in filter 'valdateNamespaces'.

isWellformedNSDecl              :: QName -> Bool
isWellformedNSDecl n            = not (isNameSpaceName n)
                                  ||
                                  isWellformedNameSpaceName n

-- |
-- test for a namespace name to be well formed

isWellformedNameSpaceName               :: QName -> Bool
isWellformedNameSpaceName (LP lp)       = lp == xmlnsXName
isWellformedNameSpaceName (PX px n)     = px == xmlnsXName
                                          &&
                                          not (null lp')
                                          &&
                                          not (a_xml `isPrefixOf` lp')
                                          where
                                          lp' = localPart n
isWellformedNameSpaceName (NS _ n)      = isWellformedNSDecl n

-- |
-- test whether a name is a namespace declaration attribute name

isNameSpaceName                 :: QName -> Bool
isNameSpaceName (LP lp)         = lp == xmlnsXName
isNameSpaceName (PX px _)       = px == xmlnsXName
isNameSpaceName (NS _  n)       = isNameSpaceName n

-- |
--
-- predicate is used in filter 'valdateNamespaces'.

isDeclaredNamespace             :: QName -> Bool
isDeclaredNamespace (NS ns n)   = isNS ns        n
isDeclaredNamespace        n    = isNS nullXName n

isNS                            :: XName -> QName -> Bool
isNS _  (LP _)                  = True                          -- no namespace used
isNS ns (PX px _)
    | px == xmlnsXName          = ns == xmlnsNamespaceXName     -- "xmlns" has a predefined namespace uri
    | px == xmlXName            = ns == xmlNamespaceXName       -- "xml" has a predefiend namespace"
    | otherwise                 = ns /= nullXName               -- namespace values are not empty
isNS ns (NS _ n)                = isNS ns n                     -- this does not occur, but warning is prevented

-- -----------------------------------------------------------------------------

toNsEnv                         :: AssocList String String -> NsEnv
toNsEnv                         = map (newXName *** newXName)

-- -----------------------------------------------------------------------------

-- the name cache, same implementation strategy as in Data.Atom,
-- but conversion to and from ByteString prevented

type Atoms      = M.Map String String

newtype Atom    = A String
                  deriving (Eq, Ord, Typeable)

-- ------------------------------------------------------------

-- | the internal cache for the strings

theAtoms        :: MVar Atoms
theAtoms        = unsafePerformIO (newMVar M.empty)
{-# NOINLINE theAtoms #-}

-- | insert a bytestring into the atom cache

insertAtom      :: String -> Atoms -> (Atoms, Atom)
insertAtom s m  = maybe (M.insert {- (trace (show s) s) -} s s m, deepseq s (A s))
                        (\ s' -> (m, A s'))
                  .
                  M.lookup s $ m

-- | creation of an @Atom@ from a @String@

newAtom         :: String -> Atom
newAtom         = unsafePerformIO . newAtom'
{-# NOINLINE newAtom #-}

-- | The internal operation running in the IO monad
newAtom'        :: String -> IO Atom
newAtom' s      = do
                  m <- takeMVar theAtoms
                  let (m', a) = insertAtom s m
                  putMVar theAtoms m'
                  return a

instance Read Atom where
    readsPrec p str = [ (newAtom x, y) | (x, y) <- readsPrec p str ]

instance Show Atom where
    show (A s)  = s

instance NFData Atom where

-----------------------------------------------------------------------------
