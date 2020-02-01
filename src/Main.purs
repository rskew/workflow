module Main where

import Prelude

import Control.Coroutine as CR
import Control.Coroutine.Aff (emit)
import Control.Coroutine.Aff as CRA
import Control.Monad.Except (runExcept)
import Data.Bifunctor (lmap)
import Data.Either (Either(..), either)
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Foreign (F, Foreign, renderForeignError, unsafeToForeign, readString)
import Foreign.Generic (encodeJSON, decodeJSON)
import GraphComponent (graphComponent)
import GraphComponent.Types (Message(..), Query(..))
import Halogen as H
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Web.Event.EventTarget as EET
import Web.HTML (window)
import Web.HTML.Window (innerWidth, innerHeight)
import Web.Socket.Event.EventTypes as WSET
import Web.Socket.Event.MessageEvent as ME
import Web.Socket.WebSocket as WS
import WireData (WireDataRaw, decodeWireData, encodeWireData)


---- Websocket stuff from
---- https://github.com/slamdata/purescript-halogen/blob/master/examples/driver-websockets/src/Main.purs

-- A producer coroutine that emits messages that arrive from the websocket.
wsProducer :: WS.WebSocket -> CR.Producer String Aff Unit
wsProducer socket = CRA.produce \emitter -> do
  listener <- EET.eventListener \ev -> do
    for_ (ME.fromEvent ev) \msgEvent ->
      for_ (readHelper readString (ME.data_ msgEvent)) \msg ->
        emit emitter msg
  EET.addEventListener
    WSET.onMessage
    listener
    false
    (WS.toEventTarget socket)
  where
    readHelper :: forall a b. (Foreign -> F a) -> b -> Maybe a
    readHelper read =
      either (const Nothing) Just <<< runExcept <<< read <<< unsafeToForeign

-- A consumer coroutine that takes the `query` function from our component IO
-- record and sends `ReceiveMessage` queries in when it receives inputs from the
-- producer.
wsConsumer :: (forall a. Query a -> Aff (Maybe a)) -> CR.Consumer String Aff Unit
wsConsumer query = CR.consumer \msg -> do
  case
    lmap (show <<< map renderForeignError)
    $ runExcept $ (decodeJSON msg :: F WireDataRaw) >>= decodeWireData
  of
    Left errors -> do
      Console.log $ "received operation but could not decode: " <> errors
      pure Nothing
    Right wireData -> do
      Console.log $ "received operation: " <> show wireData.op
      void $ query $ H.tell $ ReceiveOperation wireData.op
      pure Nothing

-- A consumer coroutine that takes output messages from our component IO
-- and sends them using the websocket
wsSender :: WS.WebSocket -> CR.Consumer Message Aff Unit
wsSender socket = CR.consumer \msg -> do
  case msg of
    SendOperation operation -> do
      encodedOperation <- liftEffect $ encodeJSON <$> encodeWireData operation
      liftEffect $ WS.sendString socket encodedOperation
  pure Nothing

main :: Effect Unit
main = do
  -- TODO
  -- connection <- WS.create config.webSocketAddress []
  connection <- WS.create "ws://localhost:8111" []
  HA.runHalogenAff do
    body <- HA.awaitBody
    w <- H.liftEffect window
    windowWidth <- H.liftEffect $ innerWidth w
    windowHeight <- H.liftEffect $ innerHeight w
    ui <- runUI
          graphComponent
          { width  : toNumber windowWidth
          , height : toNumber windowHeight
          }
          body

    -- TODO
    pure unit

    -- The wsSender consumer subscribes to all output messages
    -- from our component
    -- ui.subscribe $ wsSender connection

    -- Connecting the consumer to the producer initializes both,
    -- feeding queries back to our component as messages are received.
    -- CR.runProcess (wsProducer connection CR.$$ wsConsumer ui.query)
