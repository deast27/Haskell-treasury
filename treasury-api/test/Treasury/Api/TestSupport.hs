-- | Spins up the API against the test database, truncating it before each spec item.
module Treasury.Api.TestSupport
  ( withApp,
    postJson,
    postJsonWith,
    bodyField,
  )
where

import Data.Aeson (FromJSON, ToJSON, Value, decode, encode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (parseMaybe, withObject, (.:))
import Data.ByteString.Char8 qualified as BS8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Database.Persist.Sql (rawExecute)
import Network.HTTP.Types (Header, methodPost)
import Network.Wai (Application)
import Network.Wai.Test (SResponse (..))
import System.Environment (lookupEnv)
import Test.Hspec
import Test.Hspec.Wai
import Treasury.Api.Application (makeApplication, makeFoundation)
import Treasury.Api.Foundation (App (..))
import Treasury.Config (Config (..))
import Treasury.Db (runDb)
import Treasury.Ledger (ensureSystemAccounts)

testConfig :: IO Config
testConfig = do
  url <- fromMaybe "postgresql://treasury@localhost:5433/treasury_test" <$> lookupEnv "TEST_DATABASE_URL"
  pure Config {databaseUrl = BS8.pack url, partnerBaseUrl = "http://localhost:9400", port = 0, poolSize = 2}

makeTestApp :: IO Application
makeTestApp = do
  app <- testConfig >>= makeFoundation
  runDb app.appPool $ do
    rawExecute "TRUNCATE business, account, journal, ledger_entry, payment, webhook_outbox, audit_log RESTART IDENTITY CASCADE" []
    ensureSystemAccounts
  makeApplication app

withApp :: SpecWith ((), Application) -> Spec
withApp = with makeTestApp

postJson :: (ToJSON a) => BS8.ByteString -> a -> WaiSession st SResponse
postJson path = postJsonWith path []

postJsonWith :: (ToJSON a) => BS8.ByteString -> [Header] -> a -> WaiSession st SResponse
postJsonWith path extra body =
  request methodPost path (("Content-Type", "application/json") : extra) (encode body)

bodyField :: (FromJSON a) => Text -> SResponse -> Maybe a
bodyField field resp = do
  v <- decode (simpleBody resp) :: Maybe Value
  parseMaybe (withObject "body" (.: Key.fromText field)) v
