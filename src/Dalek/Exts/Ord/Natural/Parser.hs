{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications      #-}

module Dalek.Exts.Ord.Natural.Parser where

import           Dalek.Core
import           Dalek.Exts.Ord.Natural.Core (DhNaturalOrd)
import           Dalek.Parser


parser :: Member DhNaturalOrd fs => OpenParser fs
parser = sendParser (reservedEnumF @DhNaturalOrd)
