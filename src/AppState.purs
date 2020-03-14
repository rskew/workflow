module AppState where

import Prelude

import ContentEditable.SVGComponent as SVGContentEditable
import Data.Argonaut.Core (Json)
import Data.Array as Array
import Data.Generic.Rep (class Generic)
import Data.Lens (Lens', Traversal', lens, traversed, (%~), (?~))
import Data.Lens.At (at)
import Data.Lens.Record (prop)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple)
import Data.UUID (UUID)
import Foreign.Class (class Encode, class Decode)
import Foreign.Generic (genericEncode, genericDecode, defaultOptions)
import Halogen as H
import Halogen.Component.Utils.Drag as Drag
import Megagraph (Edge, EdgeId, EdgeMappingEdge, EdgeMetadata, GraphEdgeSpacePoint2D, GraphId, GraphSpacePoint2D(..), GraphView, Mapping, MappingId, Megagraph, MegagraphElement, Node, NodeId, NodeMappingEdge, PageEdgeSpacePoint2D, PageSpacePoint2D, Point2D, emptyMegagraph)
import MegagraphOperation (MegagraphComponent(..), MegagraphUpdate)
import Web.Event.Event as WE
import Web.File.FileReader as FileReader
import Web.HTML.HTMLElement as WHE
import Web.UIEvent.KeyboardEvent as KE
import Web.UIEvent.MouseEvent as ME
import Web.UIEvent.WheelEvent as WhE

appStateVersion :: String
appStateVersion = "0.0.0.0.0.0.0.1"

------
-- Types

data Action
  = DoMany (Array Action)
  | PreventDefault WE.Event
  | StopPropagation WE.Event
  | EvalQuery (Query Unit)
  | Init
  | LoadGraph GraphId
  | UpdateContentEditableText GraphId
  | UpdateNodeContentEditableText GraphId NodeId
  | BackgroundDragStart GraphId PageSpacePoint2D ME.MouseEvent
  | BackgroundDragMove Drag.DragEvent GraphId PageSpacePoint2D H.SubscriptionId
  | NodeDragStart GraphId NodeId GraphSpacePoint2D ME.MouseEvent
  | NodeDragMove Drag.DragEvent GraphId NodeId GraphSpacePoint2D H.SubscriptionId
  | EdgeDragStart GraphId EdgeId GraphEdgeSpacePoint2D ME.MouseEvent
  | EdgeDragMove Drag.DragEvent GraphId EdgeId GraphEdgeSpacePoint2D H.SubscriptionId
  | NodeMappingEdgeDragStart MappingId NodeMappingEdge ME.MouseEvent
  | NodeMappingEdgeDragMove Drag.DragEvent Mapping EdgeId PageEdgeSpacePoint2D H.SubscriptionId
  | EdgeMappingEdgeDragStart MappingId EdgeMappingEdge ME.MouseEvent
  | EdgeMappingEdgeDragMove Drag.DragEvent Mapping EdgeId PageEdgeSpacePoint2D H.SubscriptionId
  | EdgeDrawStart GraphView EdgeSourceElement ME.MouseEvent
  | EdgeDrawMove Drag.DragEvent GraphId DrawingEdgeId H.SubscriptionId
  | NodeTextInput GraphId NodeId String
  | EdgeTextInput GraphId EdgeId String
  | TitleTextInput GraphId String
  | UpdateTitleValidity GraphId Boolean
  | AppCreateNode GraphView ME.MouseEvent
  | AppDeleteNode Node
  | AppCreateEdge EdgeMetadata
  | AppDeleteEdge Edge
  | AppCreateNodeMappingEdge EdgeId NodeId GraphId NodeId GraphId
  | AppDeleteNodeMappingEdge MappingId EdgeId
  | AppCreateEdgeMappingEdge EdgeId EdgeId GraphId EdgeId GraphId
  | AppDeleteEdgeMappingEdge MappingId EdgeId
  | UpdateNodeSubgraph GraphId NodeId (Maybe GraphId)
  | UpdateFocus (Maybe MegagraphElement)
  | UpdateFocusPane MegagraphComponent
  | DeleteFocus
  | Hover HoveredElementId
  | UnHover HoveredElementId
  | OnFocusText TextFieldElement (String -> Maybe (Tuple MegagraphUpdate MegagraphComponent))
  | OnBlurText
  | BlurFocusedTextField
  | Zoom GraphId WhE.WheelEvent
  | CenterGraphOriginAndZoom
  | Undo MegagraphComponent
  | Redo MegagraphComponent
  | RemovePane GraphId
  | FetchLocalFile WE.Event
  | LoadLocalFile FileReader.FileReader H.SubscriptionId WE.Event
  | SaveLocalFile
  | Keypress KE.KeyboardEvent
  | Keyup KE.KeyboardEvent
  | DoNothing

data TextFieldElement
  = NodeTextField GraphId NodeId
  | EdgeTextField GraphId EdgeId
  | TitleTextField GraphId

derive instance eqTextFieldElement :: Eq TextFieldElement

type Input = Shape

data Query a
  = UpdateBoundingRect a
  | ReceiveOperation String Json a
  | QLoadGraph GraphId a

data Message
  = SendOperation String

-- Slot type for parent components using a child GraphComponent
type Slot = H.Slot Query Message

type Slots =
  ( nodeTextField  :: SVGContentEditable.Slot NodeId
  , edgeTextField  :: SVGContentEditable.Slot EdgeId
  , titleTextField :: SVGContentEditable.Slot GraphId
  )

_nodeTextField :: SProxy "nodeTextField"
_nodeTextField = SProxy

_edgeTextField :: SProxy "edgeTextField"
_edgeTextField = SProxy

_titleTextField :: SProxy "titleTextField"
_titleTextField = SProxy

type KeyHoldState
  = { spaceDown   :: Boolean
    , controlDown :: Boolean
    }

type ComponentHistory
  = { history :: Array MegagraphUpdate
    , undone  :: Array MegagraphUpdate
    }

freshComponentHistory :: ComponentHistory
freshComponentHistory
  = { history: []
    , undone: []
    }

type History
  = { graphHistory   :: Map GraphId ComponentHistory
    , mappingHistory :: Map MappingId ComponentHistory
    }

emptyHistory :: History
emptyHistory = { graphHistory: Map.empty, mappingHistory: Map.empty}

type AppState
  = { megagraph          :: Megagraph
    , megagraphHistory   :: History
    , windowBoundingRect :: WHE.DOMRect
    , drawingEdges       :: Map DrawingEdgeId DrawingEdge
    , hoveredElements    :: Set HoveredElementId
    , focus              :: Maybe MegagraphElement
    , focusedPane        :: Maybe MegagraphComponent
    , textFocused        :: Maybe { historyUpdater :: (String -> Maybe (Tuple MegagraphUpdate MegagraphComponent))
                                  , textFieldElement :: TextFieldElement
                                  }
    , keyHoldState       :: KeyHoldState
    -- Each active conversation is kept track of via an id, with the handler
    -- for the next incoming message indexed by the id.
    , callbacks          :: Map String (Json -> Maybe Action)
    -- The elements pending a server query are kept track of in a Map,
    -- with the element id as the key and the callbackId / conversation id
    -- as the value.
    , pending            :: Map UUID String
    }

emptyAppState :: WHE.DOMRect -> AppState
emptyAppState rect
  = { megagraph          : emptyMegagraph
    , megagraphHistory   : emptyHistory
    , windowBoundingRect : rect
    , drawingEdges       : Map.empty
    , hoveredElements    : Set.empty
    , focus              : Nothing
    , focusedPane        : Nothing
    , textFocused        : Nothing
    , keyHoldState       : { spaceDown : false, controlDown : false }
    , callbacks          : Map.empty
    , pending            : Map.empty
    }

data HistoryUpdate
  = Insert MegagraphUpdate
  | Pop
  | Replace (Array MegagraphUpdate)
  | NoOp

derive instance genericHistoryUpdate :: Generic HistoryUpdate _
instance decodeHistoryUpdate :: Decode HistoryUpdate where
  decode = genericDecode defaultOptions
instance encodeHistoryUpdate :: Encode HistoryUpdate where
  encode = genericEncode defaultOptions

instance showHistoryUpdate :: Show HistoryUpdate where
  show = case _ of
    Insert op -> "Insert " <> show op
    Pop -> "Pop"
    Replace megagraphUpdate -> "Replace " <> show megagraphUpdate
    NoOp -> "NoOp"

updateHistoryArray :: HistoryUpdate -> Array MegagraphUpdate -> Array MegagraphUpdate
updateHistoryArray = case _ of
  Insert op -> Array.cons op
  Pop -> Array.drop 1
  Replace newHistory -> const newHistory
  NoOp -> identity

updateHistory :: HistoryUpdate -> MegagraphComponent -> AppState -> AppState
updateHistory historyUpdate target state =
  let
    updateComponentHistory target' = case target' of
      GraphComponent graphId ->
        (case Map.lookup graphId state.megagraphHistory.graphHistory of
          Nothing -> _graphHistory <<< at graphId ?~ freshComponentHistory
          Just graphHistory -> identity)
        >>>
        (_graphHistory <<< at graphId <<< traversed <<< _history %~ updateHistoryArray historyUpdate)
      MappingComponent mappingId from to ->
        (case Map.lookup mappingId state.megagraphHistory.mappingHistory of
            Nothing -> _mappingHistory <<< at mappingId ?~ freshComponentHistory
            Just mappingHistory -> identity)
        >>>
        (_mappingHistory <<< at mappingId <<< traversed <<< _history %~ updateHistoryArray historyUpdate)
  in
    state
    # _megagraphHistory %~ updateComponentHistory target

updateUndone :: HistoryUpdate -> MegagraphComponent -> AppState -> AppState
updateUndone undoneUpdate target state =
  let
    updateComponentHistory target' = case target' of
      GraphComponent graphId ->
        _graphHistory <<< at graphId <<< traversed <<< _undone %~ updateHistoryArray undoneUpdate
      MappingComponent mappingId from to ->
        _mappingHistory <<< at mappingId <<< traversed <<< _undone %~ updateHistoryArray undoneUpdate
  in
    state
    # _megagraphHistory %~ updateComponentHistory target

type Shape
  = { width :: Number
    , height :: Number
    }

edgeIdStr :: Edge -> String
edgeIdStr edge = show edge.source <> "_" <> show edge.target

data EdgeSourceElement
  = NodeSource NodeId
  | EdgeSource EdgeId

derive instance eqEdgeSourceElement :: Eq EdgeSourceElement

instance showEdgeSourceElement :: Show EdgeSourceElement where
  show = case _ of
    NodeSource nodeId -> "EdgeSourceElement NodeSource " <> show nodeId
    EdgeSource edgeId -> "EdgeSourceElement EdgeSource " <> show edgeId

type DrawingEdge
  = { source         :: EdgeSourceElement
    , sourcePosition :: PageSpacePoint2D
    , sourceGraph    :: GraphId
    , pointPosition  :: PageSpacePoint2D
    , targetGraph    :: GraphId
    }

type DrawingEdgeId = UUID

data HoveredElementId
  = NodeHaloId   GraphId            NodeId
  | NodeBorderId GraphId            NodeId
  | EdgeHaloId   MegagraphComponent EdgeId
  | EdgeBorderId MegagraphComponent EdgeId

derive instance eqHoveredElementId :: Eq HoveredElementId

derive instance ordHoveredElementId :: Ord HoveredElementId

instance showHoveredElementId :: Show HoveredElementId where
   show = case _ of
     NodeHaloId   graphId nodeId -> "NodeHaloId in graph: " <> show graphId <> " node: " <> show nodeId
     NodeBorderId graphId nodeId -> "NodeBorderId in graph: " <> show graphId <> " node: " <> show nodeId
     EdgeHaloId   graphId edgeId -> "EdgeHaloId in graph: " <> show graphId <> " edge: " <> show edgeId
     EdgeBorderId graphId edgeId -> "EdgeBorderId in graph: " <> show graphId <> "  edge: " <> show edgeId


------
-- Lenses

_drawingEdges :: Lens' AppState (Map DrawingEdgeId DrawingEdge)
_drawingEdges = prop (SProxy :: SProxy "drawingEdges")

_drawingEdgePosition :: DrawingEdgeId -> Traversal' AppState PageSpacePoint2D
_drawingEdgePosition drawingEdgeId =
  _drawingEdges <<< at drawingEdgeId <<< traversed <<< prop (SProxy :: SProxy "pointPosition")

_drawingEdgeTargetGraph :: DrawingEdgeId -> Traversal' AppState GraphId
_drawingEdgeTargetGraph drawingEdgeId =
  _drawingEdges <<< at drawingEdgeId <<< traversed <<< prop (SProxy :: SProxy "targetGraph")

_megagraph :: Lens' AppState Megagraph
_megagraph = prop (SProxy :: SProxy "megagraph")

_windowBoundingRect :: Lens' AppState WHE.DOMRect
_windowBoundingRect = prop (SProxy :: SProxy "windowBoundingRect")

_coerceToGraphSpace :: Lens' Point2D GraphSpacePoint2D
_coerceToGraphSpace = lens GraphSpacePoint2D (\_ (GraphSpacePoint2D pos) -> pos)

_megagraphHistory :: Lens' AppState History
_megagraphHistory = prop (SProxy :: SProxy "megagraphHistory")

_graphHistory :: Lens' History (Map GraphId ComponentHistory)
_graphHistory = prop (SProxy :: SProxy "graphHistory")

_mappingHistory :: Lens' History (Map MappingId ComponentHistory)
_mappingHistory = prop (SProxy :: SProxy "graphHistory")

_history :: Lens' ComponentHistory (Array MegagraphUpdate)
_history = prop (SProxy :: SProxy "history")

_undone :: Lens' ComponentHistory (Array MegagraphUpdate)
_undone = prop (SProxy :: SProxy "undone")

_focusedPane :: Lens' AppState (Maybe MegagraphComponent)
_focusedPane = prop (SProxy :: SProxy "focusedPane")

_hoveredElements :: Lens' AppState (Set HoveredElementId)
_hoveredElements = prop (SProxy :: SProxy "hoveredElements")

_keyHoldState :: Lens' AppState KeyHoldState
_keyHoldState = prop (SProxy :: SProxy "keyHoldState")

_spaceDown :: Lens' KeyHoldState Boolean
_spaceDown = prop (SProxy :: SProxy "spaceDown")

_controlDown :: Lens' KeyHoldState Boolean
_controlDown = prop (SProxy :: SProxy "controlDown")

_callbacks :: Lens' AppState (Map String (Json -> Maybe Action))
_callbacks = prop (SProxy :: SProxy "callbacks")

_pending :: Lens' AppState (Map UUID String)
_pending = prop (SProxy :: SProxy "pending")

------
-- Utils

-- | There is only a sinlge mapping present n in the state between any two graphs,
-- | so mappings can be found uniquely by their source and target graphs.
lookupMapping :: GraphId -> GraphId -> AppState -> Maybe Mapping
lookupMapping sourceGraphId targetGraphId state =
  state.megagraph.mappings
  # Map.values >>> Array.fromFoldable
  # Array.filter (\mapping -> mapping.sourceGraph == sourceGraphId
                           && mapping.targetGraph == targetGraphId)
  # Array.head
