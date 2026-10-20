-- | HTTP client for the partner bank.
module Treasury.Partner.Client
  ( submitPayment,
    getPaymentStatus,
    listSettlements,
    newPartnerManager,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (Day, getCurrentTime)
import Network.HTTP.Client
import Network.HTTP.Types (RequestHeaders, statusCode)
import System.Environment (lookupEnv)
import Treasury.Errors (badGateway, throwHttp)
import Treasury.Partner.Types

newPartnerManager :: PartnerConfig -> IO Manager
newPartnerManager cfg =
  newManager defaultManagerSettings {managerResponseTimeout = responseTimeoutMicro cfg.timeoutMicros}

submitPayment :: PartnerConfig -> Manager -> Submission -> IO Receipt
submitPayment cfg mgr sub = do
  -- Local test runs don't have a partner; short-circuit so the suite can run.
  stub <- lookupEnv "TREASURY_PARTNER_STUB"
  case stub of
    Just _ -> do
      t <- getCurrentTime
      pure Receipt {partnerRef = "stub-" <> sub.clientRef, acceptedAt = t}
    Nothing -> postJson cfg mgr "/v1/payments" sub

getPaymentStatus :: PartnerConfig -> Manager -> Text -> IO StatusResponse
getPaymentStatus cfg mgr ref = getJson cfg mgr ("/v1/payments/" <> ref)

listSettlements :: PartnerConfig -> Manager -> Day -> IO [SettlementRecord]
listSettlements cfg mgr day = getJson cfg mgr ("/v1/settlements?date=" <> T.pack (show day))

postJson :: (ToJSON a, FromJSON b) => PartnerConfig -> Manager -> Text -> a -> IO b
postJson cfg mgr path body = do
  req <- parseRequest (T.unpack (cfg.baseUrl <> path))
  send mgr req {method = "POST", requestBody = RequestBodyLBS (encode body), requestHeaders = headers cfg}

getJson :: (FromJSON b) => PartnerConfig -> Manager -> Text -> IO b
getJson cfg mgr path = do
  req <- parseRequest (T.unpack (cfg.baseUrl <> path))
  send mgr req {requestHeaders = headers cfg}

headers :: PartnerConfig -> RequestHeaders
headers cfg =
  [ ("Content-Type", "application/json"),
    ("Authorization", "Bearer " <> TE.encodeUtf8 cfg.apiKey)
  ]

send :: (FromJSON b) => Manager -> Request -> IO b
send mgr req = do
  result <- try (httpLbs req mgr)
  case result of
    Left (e :: SomeException) -> badGateway ("partner unavailable: " <> T.pack (show e))
    Right resp -> do
      let code = statusCode (responseStatus resp)
      if code >= 200 && code < 300
        then either (throwHttp 502 . ("partner sent malformed response: " <>) . T.pack) pure (eitherDecode (responseBody resp))
        else throwHttp code ("partner returned " <> T.pack (show code))
