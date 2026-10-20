-- | Process configuration, read from the environment.
module Treasury.Config
  ( Config (..),
    loadConfig,
  )
where

import Data.ByteString.Char8 qualified as BS8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data Config = Config
  { databaseUrl :: BS8.ByteString,
    partnerBaseUrl :: Text,
    port :: Int,
    poolSize :: Int
  }
  deriving stock (Show)

loadConfig :: IO Config
loadConfig = do
  databaseUrl <- BS8.pack . fromMaybe "postgresql://treasury@localhost:5433/treasury" <$> lookupEnv "DATABASE_URL"
  partnerBaseUrl <- T.pack . fromMaybe "http://localhost:9400" <$> lookupEnv "PARTNER_BASE_URL"
  port <- maybe 8080 (fromMaybe 8080 . readMaybe) <$> lookupEnv "PORT"
  poolSize <- maybe 10 (fromMaybe 10 . readMaybe) <$> lookupEnv "DB_POOL_SIZE"
  pure Config {..}
