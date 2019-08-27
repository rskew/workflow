module Workflow.UIGraph.UIGraphOp where

import Prelude

import Control.Monad.Free (Free, hoistFree, liftF, resume)
import Data.Either (Either(..))
import Data.Group (class Group)
import Data.Lens (traversed, (^.), (.~))
import Data.Lens.At (at)
import Data.Monoid.Action (class Action)
import Workflow.Core (_edgeId, _id, _nodes, deleteEdge, deleteNode, insertEdge, insertNode, modifyEdge)
import Workflow.UIGraph (UIGraph, UINode, UIEdge, Point2D, _pos, _nodeText, _edgeText)

------
-- Free Monad DSL
--
-- Mostly for supporting Undoable

data UIGraphOpF next
  = InsertNode UINode next
  | DeleteNode UINode next
  | InsertEdge UIEdge next
  | DeleteEdge UIEdge next
  | MoveNode UINode Point2D Point2D next
  | UpdateNodeText UINode String String next
  | UpdateEdgeText UIEdge String String next
  | NoOp next
derive instance functorUIGraphOpF :: Functor UIGraphOpF

type UIGraphOpM = Free UIGraphOpF

newtype UIGraphOp a = UIGraphOp (UIGraphOpM a)

-- | Group instance required by Undoable
instance semigroupUIGraphOp :: Semigroup (UIGraphOp a) where
  append (UIGraphOp op1) (UIGraphOp op2) = UIGraphOp $ op1 >>= \_ -> op2
instance monoidUIGraphOp :: Monoid a => Monoid (UIGraphOp a) where
  mempty = UIGraphOp $ liftF $ NoOp mempty
instance groupUIGraphOp :: Monoid a => Group (UIGraphOp a) where
  ginverse (UIGraphOp op) = UIGraphOp $ (hoistFree invert) op where
    invert :: UIGraphOpF ~> UIGraphOpF
    invert op' = case op' of
      InsertNode node next             -> DeleteNode node next
      DeleteNode node next             -> InsertNode node next
      InsertEdge edge next             -> DeleteEdge edge next
      DeleteEdge edge next             -> InsertEdge edge next
      MoveNode node from to next       -> MoveNode node to from next
      UpdateNodeText node from to next -> UpdateNodeText node to from next
      UpdateEdgeText edge from to next -> UpdateEdgeText edge to from next
      NoOp next                        -> NoOp next


------
-- Interpreter

interpretUIGraphOp :: forall a. UIGraphOp a -> (UIGraph -> UIGraph)
interpretUIGraphOp (UIGraphOp op) = case resume op of
  Right _ -> identity
  Left (InsertNode node next) ->
    (insertNode node)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (DeleteNode node next) ->
    (deleteNode node)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (InsertEdge edge next) ->
    (insertEdge edge)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (DeleteEdge edge next) ->
    (deleteEdge edge)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (MoveNode node from to next) ->
    (_nodes <<< at (node ^. _id) <<< traversed <<< _pos .~ to)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (UpdateNodeText node from to next) ->
    (_nodes <<< at (node ^. _id) <<< traversed <<< _nodeText .~ to)
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (UpdateEdgeText edge from to next) ->
    (modifyEdge (edge ^. _edgeId) (_edgeText .~ to))
    >>> (interpretUIGraphOp $ UIGraphOp next)
  Left (NoOp next) ->
    interpretUIGraphOp $ UIGraphOp next


-- | Action instance required by Undoable
instance actUIGraphOpUIGraph :: Action (UIGraphOp a) UIGraph where
  act op = interpretUIGraphOp op

insertNodeOp :: UINode -> UIGraphOp Unit
insertNodeOp node = UIGraphOp $ liftF $ InsertNode node unit