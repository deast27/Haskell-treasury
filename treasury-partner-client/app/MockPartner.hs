{-# LANGUAGE NumericUnderscores #-}

-- | A stand-in for the partner bank, for local development and demos.
--
-- Behaviour is deterministic so that scenarios can be scripted:
--
--   * amounts ending in 13 cents are returned by the receiving bank after
--     acknowledgement (e.g. 100013 = $1,000.13);
--   * amounts ending in 99 cents are rejected outright;
--   * counterparty names containing "slow" take 15 s to respond.
--
-- Payments advance one state every 5 seconds after submission.
module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Data.Aeson (ToJSON, Value, decode, encode, object, toJSON, (.=))
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Treasury.Partner.Types

data Stored = Stored
  { submission :: Submission,
    receivedAt :: UTCTime
  }

main :: IO ()
main = do
  port <- maybe 9400 (fromMaybe 9400 . readMaybe) <$> lookupEnv "MOCK_PARTNER_PORT"
  store <- newIORef (Map.empty :: Map.Map Text Stored)
  putStrLn ("mock-partner listening on :" <> show port)
  run port (app store)

app :: IORef (Map.Map Text Stored) -> Application
app store req respond = case (requestMethod req, pathInfo req) of
  ("POST", ["v1", "payments"]) -> do
    body <- strictRequestBody req
    case decode body of
      Nothing -> respond (jsonResponse status400 (object ["error" .= ("malformed submission" :: Text)]))
      Just sub -> do
        when ("slow" `T.isInfixOf` T.toLower sub.counterpartyName) $ threadDelay 15_000_000
        t <- getCurrentTime
        let ref = "PB-" <> T.takeEnd 12 (T.filter (/= '-') sub.clientRef)
        atomicModifyIORef' store (\m -> (Map.insert ref (Stored sub t) m, ()))
        putStrLn ("accepted " <> T.unpack ref <> " for " <> show sub.amountCents <> " cents")
        respond (jsonResponse status201 (encodeValue Receipt {partnerRef = ref, acceptedAt = t}))
  ("GET", ["v1", "payments", ref]) -> do
    m <- readIORef store
    case Map.lookup ref m of
      Nothing -> respond (jsonResponse status404 (object ["error" .= ("unknown payment" :: Text)]))
      Just s -> do
        t <- getCurrentTime
        let (st, reason) = statusAt t s
        respond (jsonResponse status200 (encodeValue StatusResponse {partnerRef = ref, status = st, reason, updatedAt = t}))
  ("GET", ["v1", "settlements"]) -> do
    m <- readIORef store
    t <- getCurrentTime
    let settled =
          [ SettlementRecord {partnerRef = ref, clientRef = s.submission.clientRef, amountCents = s.submission.amountCents, settledOn = utctDay t}
          | (ref, s) <- Map.toList m,
            fst (statusAt t s) == SettledByPartner
          ]
    respond (jsonResponse status200 (encodeValue settled))
  _ -> respond (jsonResponse status404 (object ["error" .= ("no such route" :: Text)]))
  where
    encodeValue :: (ToJSON a) => a -> Value
    encodeValue = toJSON

statusAt :: UTCTime -> Stored -> (PartnerStatus, Maybe Text)
statusAt t s =
  let age = realToFrac (diffUTCTime t s.receivedAt) :: Double
      lastTwo = s.submission.amountCents `mod` 100
   in if
        | lastTwo == 99 -> (Rejected, Just "R03: no account/unable to locate account")
        | age < 5 -> (Accepted, Nothing)
        | age < 10 -> (Acknowledged, Nothing)
        | lastTwo == 13 -> (Returned, Just "R01: insufficient funds at receiving bank")
        | otherwise -> (SettledByPartner, Nothing)

jsonResponse :: Status -> Value -> Response
jsonResponse st v = responseLBS st [(hContentType, "application/json")] (encode v)
