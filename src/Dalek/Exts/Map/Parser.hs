{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}

module Dalek.Exts.Map.Parser where

import           Data.Foldable       (asum)
import           Data.Text.Buildable (Buildable)

import           Dalek.Core
import           Dalek.Exts.Map.Core (DhMap (..))
import           Dalek.Parser

parser :: (Buildable (Open fs), Member DhMap fs) => OpenParser fs
parser = sendParser $ asum $ fmap (reservedF @DhMap) $
  [ DhMapEmpty
  , DhMapSingleton
  , DhMapLookup
  , DhMapInsert
  , DhMapFromList
  , DhMapTy
  ]
