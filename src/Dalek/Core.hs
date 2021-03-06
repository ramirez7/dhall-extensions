{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE TypeSynonymInstances       #-}
{-# LANGUAGE UndecidableInstances       #-}

module Dalek.Core
  ( -- * Extensible Normalization
    OpenNormalizer
  , Open
  , OpenExpr
  , sendEmbed
  , (.<|>)
  , ignoringUnclosed
  -- * Note
  , unNote
  , reNote
  -- * Utilities
  , C (..)
  , xNormalizer
  , IsOpen
  , OpenSatisfies
  , isClosedExpression
  -- * Re-exports
  , Member
  , Members
  , X(..)
  , inj
  , prj
  -- * Internals
  , DalekUnion (..)
  , Rec (..)
  ,
  ) where

import           Control.Applicative
import           Control.Monad             (guard)
import           Control.Monad.Trans.Maybe (MaybeT (..))
import           Data.Bifunctor            (first)
import           Data.Kind                 (Constraint)
import           Data.Open.Union
import           Data.Text.Buildable       (Buildable (..))

import qualified Dhall.Core                as Dh

-- TODO: Re-export this when it has an Ord instance upstream.
--import           Dhall.TypeCheck           (X (..))

-- TODO: IDEA: :git ghci command lol
{-
λ: :kind! Dh.Normalizer Int Bool
Dh.Normalizer Int Bool :: *
= Dh.Normalizer Int Bool
λ: type family Id a where Id a = a
λ: :kind! Id (Dh.Normalizer Int Bool)
Id (Dh.Normalizer Int Bool) :: *
= Dh.Expr Int Bool -> Maybe (Dh.Expr Int Bool)
-}


-- | Dalek-owned Void
newtype X = X { absurd :: forall a . a }

instance Show X where
    show = absurd

instance Eq X where
  _ == _ = True

instance Ord X where
  compare _ _ = EQ

instance Buildable X where
    build = absurd

-- | Inspired by the "Term trick":
--
-- http://blog.sumtypeofway.com/recursion-schemes-part-41-2-better-living-through-base-functors/
--
-- This allows us to write our extensions @* -> *@ where the type variable
-- is the Dhall AST itself (along with all extensions..including the one we're writing)
--
-- This encoding allows for extensions to have recursive structures of extended Dhall ASTs
-- (for instance, containers like Map/Seq or custom AST syntax)
newtype Rec f = Rec { unRec :: f (Dh.Expr X (Rec f)) }

type Open (fs :: [* -> *]) = Rec (Union fs)
type OpenExpr s (fs :: [* -> *]) = Dh.Expr s (Open fs)

type OpenNormalizer (fs :: [* -> *]) = Dh.Normalizer (Open fs)

infixl 3 .<|>
-- | Normalizer alternative. Prefers the left-hand side.
(.<|>) :: Dh.Normalizer a -> Dh.Normalizer a -> Dh.Normalizer a
nl .<|> nr = runMaybeT (MaybeT nl <|> MaybeT nr)

-- | Embed a value into an 'OpenExpr'
sendEmbed :: forall fs s f. Member f fs => f (OpenExpr X fs) -> OpenExpr s fs
sendEmbed a = Dh.Embed $ Rec $ inj a

-- | Filter terms passed to a 'Normalizer' so that no unclosed terms (i.e.
-- containing unresolved variables within) are normalized using it. This helps
-- ensure that 'Embed' terms do not capture unclosed Dhall expressions. If this
-- happens, those variables will never be resolved as 'dhall' does not
-- perform substitution on 'Embed' terms.
ignoringUnclosed :: Dh.Normalizer a -> Dh.Normalizer a
ignoringUnclosed n e = do
  guard (isClosedExpression e)
  n e

-- | The same as 'Data.Functor.Const' but with different instances
newtype C c a = C { unC :: c } deriving (Functor, Eq, Ord, Buildable, Show)

-- | Normalizer for lifted 'X'
xNormalizer :: Member (C X) fs => OpenNormalizer fs
xNormalizer = const Nothing
--------------------------------------------------------------------------------
-- Note stuff

-- | Remove all 'Note's from the AST
unNote :: Dh.Expr s a -> Dh.Expr t a
unNote = \case
  Dh.Note _ e -> unNote e
  Dh.Const x -> Dh.Const x
  Dh.Var x -> Dh.Var x
  Dh.Lam t e1 e2 -> Dh.Lam t (unNote e1) (unNote e2)
  Dh.Pi t e1 e2 -> Dh.Pi t (unNote e1) (unNote e2)
  Dh.App e1 e2 -> Dh.App (unNote e1) (unNote e2)
  Dh.Let t me1 e2 e3 -> Dh.Let t (fmap unNote me1) (unNote e2) (unNote e3)
  Dh.Annot e1 e2 -> Dh.Annot (unNote e1) (unNote e2)
  Dh.Bool -> Dh.Bool
  Dh.BoolLit b -> Dh.BoolLit b
  Dh.BoolAnd e1 e2 -> Dh.BoolAnd (unNote e1) (unNote e2)
  Dh.BoolOr e1 e2 -> Dh.BoolOr (unNote e1) (unNote e2)
  Dh.BoolEQ e1 e2 -> Dh.BoolEQ (unNote e1) (unNote e2)
  Dh.BoolNE e1 e2 -> Dh.BoolNE (unNote e1) (unNote e2)
  Dh.BoolIf e1 e2 e3 -> Dh.BoolIf (unNote e1) (unNote e2) (unNote e3)
  Dh.Natural -> Dh.Natural
  Dh.NaturalLit n -> Dh.NaturalLit n
  Dh.NaturalFold -> Dh.NaturalFold
  Dh.NaturalBuild -> Dh.NaturalBuild
  Dh.NaturalIsZero -> Dh.NaturalIsZero
  Dh.NaturalEven -> Dh.NaturalEven
  Dh.NaturalOdd -> Dh.NaturalOdd
  Dh.NaturalToInteger -> Dh.NaturalToInteger
  Dh.NaturalShow -> Dh.NaturalShow
  Dh.NaturalPlus e1 e2 -> Dh.NaturalPlus (unNote e1) (unNote e2)
  Dh.NaturalTimes e1 e2 -> Dh.NaturalTimes (unNote e1) (unNote e2)
  Dh.Integer -> Dh.Integer
  Dh.IntegerLit i -> Dh.IntegerLit i
  Dh.IntegerShow -> Dh.IntegerShow
  Dh.Double -> Dh.Double
  Dh.DoubleLit d -> Dh.DoubleLit d
  Dh.DoubleShow -> Dh.DoubleShow
  Dh.Text -> Dh.Text
  Dh.TextLit (Dh.Chunks chunks final) -> Dh.TextLit $ Dh.Chunks (fmap (\(t, e) -> (t, unNote e)) chunks) final
  Dh.TextAppend e1 e2 -> Dh.TextAppend (unNote e1) (unNote e2)
  Dh.List -> Dh.List
  Dh.ListLit me1 ve2 -> Dh.ListLit (fmap unNote me1) (fmap unNote ve2)
  Dh.ListAppend e1 e2 -> Dh.ListAppend (unNote e1) (unNote e2)
  Dh.ListBuild -> Dh.ListBuild
  Dh.ListFold -> Dh.ListFold
  Dh.ListLength -> Dh.ListLength
  Dh.ListHead -> Dh.ListHead
  Dh.ListLast -> Dh.ListLast
  Dh.ListIndexed -> Dh.ListIndexed
  Dh.ListReverse -> Dh.ListReverse
  Dh.Optional -> Dh.Optional
  Dh.OptionalLit e1 ve2  -> Dh.OptionalLit (unNote e1) (fmap unNote ve2)
  Dh.OptionalFold -> Dh.OptionalFold
  Dh.OptionalBuild -> Dh.OptionalBuild
  Dh.Record mpe -> Dh.Record (fmap unNote mpe)
  Dh.RecordLit mpe -> Dh.RecordLit (fmap unNote mpe)
  Dh.Union mpe -> Dh.Union (fmap unNote mpe)
  Dh.UnionLit t e1 mpe2 -> Dh.UnionLit t (unNote e1) (fmap unNote mpe2)
  Dh.Combine e1 e2 -> Dh.Combine (unNote e1) (unNote e2)
  Dh.Prefer e1 e2 -> Dh.Prefer (unNote e1) (unNote e2)
  Dh.Merge e1 e2 me3 -> Dh.Merge (unNote e1) (unNote e2) (fmap unNote me3)
  Dh.Constructors e -> Dh.Constructors (unNote e)
  Dh.Field e t -> Dh.Field (unNote e) t
  Dh.Embed a -> Dh.Embed a

-- | Convert a 'Note'-less AST to any other type of Noted AST
--
-- @
-- 'reNote' = 'first' 'absurd'
-- @
reNote :: Dh.Expr X a -> Dh.Expr s a
reNote = first absurd
--------------------------------------------------------------------------------
-- Closed expression validation

-- TODO: Test this
isClosedExpression :: Dh.Expr s a -> Bool
isClosedExpression = \case
  Dh.Var _ -> False
  Dh.Note _ e -> isClosedExpression e
  Dh.Const _ -> True
  Dh.Lam _ e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Pi _ e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.App e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Let _ me1 e2 e3 -> all isClosedExpression me1 && isClosedExpression e2 && isClosedExpression e3
  Dh.Annot e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Bool -> True
  Dh.BoolLit _ -> True
  Dh.BoolAnd e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.BoolOr e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.BoolEQ e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.BoolNE e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.BoolIf e1 e2 e3 -> isClosedExpression e1 && isClosedExpression e2 && isClosedExpression e3
  Dh.Natural -> True
  Dh.NaturalLit _ -> True
  Dh.NaturalFold -> True
  Dh.NaturalBuild -> True
  Dh.NaturalIsZero -> True
  Dh.NaturalEven -> True
  Dh.NaturalOdd -> True
  Dh.NaturalToInteger -> True
  Dh.NaturalShow -> True
  Dh.NaturalPlus e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.NaturalTimes e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Integer -> True
  Dh.IntegerLit _ -> True
  Dh.IntegerShow -> True
  Dh.Double -> True
  Dh.DoubleLit _ -> True
  Dh.DoubleShow -> True
  Dh.Text -> True
  Dh.TextLit (Dh.Chunks chunks _) -> all (isClosedExpression . snd) chunks
  Dh.TextAppend e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.List -> True
  Dh.ListLit me1 ve2 -> all isClosedExpression me1 && all isClosedExpression ve2
  Dh.ListAppend e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.ListBuild -> True
  Dh.ListFold -> True
  Dh.ListLength -> True
  Dh.ListHead -> True
  Dh.ListLast -> True
  Dh.ListIndexed -> True
  Dh.ListReverse -> True
  Dh.Optional -> True
  Dh.OptionalLit e1 ve2  -> isClosedExpression e1 && all isClosedExpression ve2
  Dh.OptionalFold -> True
  Dh.OptionalBuild -> True
  Dh.Record mpe -> all isClosedExpression mpe
  Dh.RecordLit mpe -> all isClosedExpression mpe
  Dh.Union mpe -> all isClosedExpression mpe
  Dh.UnionLit _ e1 mpe2 -> isClosedExpression e1 && all isClosedExpression mpe2
  Dh.Combine e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Prefer e1 e2 -> isClosedExpression e1 && isClosedExpression e2
  Dh.Merge e1 e2 me3 -> isClosedExpression e1 && isClosedExpression e2 && all isClosedExpression me3
  Dh.Constructors e -> isClosedExpression e
  Dh.Field e _ -> isClosedExpression e
  Dh.Embed _ -> True
--------------------------------------------------------------------------------
-- instances

type IsOpen s fs expr = expr ~ OpenExpr s fs

type OpenSatisfies (c :: * -> Constraint) fs = c (DalekUnion fs (OpenExpr X fs))

instance Show (DalekUnion fs (OpenExpr X fs)) => Show (Open fs) where
  show (Rec x) = show (DalekUnion x)

instance Eq (DalekUnion fs (OpenExpr X fs)) => Eq (Open fs) where
  (Rec x) == (Rec y) = DalekUnion x == DalekUnion y

instance Ord (DalekUnion fs (OpenExpr X fs)) => Ord (Open fs) where
  compare (Rec x) (Rec y) = compare (DalekUnion x) (DalekUnion y)

instance Buildable (DalekUnion fs (OpenExpr X fs)) => Buildable (Open fs) where
  build (Rec x) = build (DalekUnion x)

-- | Newtype wrapper 'OpenUnion' so we can get some non-orphan instances we need
newtype DalekUnion fs a = DalekUnion (Union fs a)

instance (Show (f a)) => Show (DalekUnion '[f] a) where
  show (DalekUnion x) = show $ extract x

instance {-# OVERLAPPABLE #-} (Show (f a), Show (DalekUnion fs a)) => Show (DalekUnion (f ': fs) a) where
  show (DalekUnion x) = case decomp x of
    Right fv -> show fv
    Left uv  -> show (DalekUnion uv)

instance (Buildable (f a)) => Buildable (DalekUnion '[f] a) where
  build (DalekUnion x) = build $ extract x

instance {-# OVERLAPPABLE #-} (Buildable (f a), Buildable (DalekUnion fs a)) => Buildable (DalekUnion (f ': fs) a) where
  build (DalekUnion x) = case decomp x of
    Right fv -> build fv
    Left uv  -> build (DalekUnion uv)

instance (Eq (f a)) => Eq (DalekUnion '[f] a) where
  (DalekUnion x) == (DalekUnion y) = extract x == extract y

instance {-# OVERLAPPABLE #-} (Eq (f a), Eq (DalekUnion fs a)) => Eq (DalekUnion (f ': fs) a) where
  (DalekUnion x) == (DalekUnion y) = case decomp x of
    Right fx -> case decomp y of
      Right fy -> fx == fy
      Left _   -> False
    Left ux -> case decomp y of
      Left uy -> DalekUnion ux == DalekUnion uy
      Right _ -> False

instance (Ord (f a)) => Ord (DalekUnion '[f] a) where
  compare (DalekUnion x) (DalekUnion y) = compare (extract x) (extract y)

instance {-# OVERLAPPABLE #-} (Ord (f a), Ord (DalekUnion fs a)) => Ord (DalekUnion (f ': fs) a) where
  compare (DalekUnion x) (DalekUnion y) = case decomp x of
    Right fx -> case decomp y of
      Right fy -> compare fx fy
      Left _   -> GT
    Left ux -> case decomp y of
      Left uy -> compare (DalekUnion ux) (DalekUnion uy)
      Right _ -> LT
