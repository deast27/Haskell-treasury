-- | Plumbing shared by the workers.
module Treasury.Workers.Shared
  ( WorkerEnv (..),
    mkWorkerEnv,
    runForever,
    logLine,
    paymentRef,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (getCurrentTime)
import Database.Persist.Sql (fromSqlKey)
import Network.HTTP.Client (Manager)
import System.IO (hFlush, stdout)
import Treasury.Config (Config (..))
import Treasury.Db (DbPool, mkPool, runMigrations)
import Treasury.Model (PaymentId)
import Treasury.Partner.Client (newPartnerManager)
import Treasury.Partner.Types (PartnerConfig (..))

data WorkerEnv = WorkerEnv
  { pool :: DbPool,
    partner :: PartnerConfig,
    manager :: Manager
  }

mkWorkerEnv :: Config -> IO WorkerEnv
mkWorkerEnv config = do
  pool <- mkPool config.databaseUrl 4
  runMigrations pool
  let partner = PartnerConfig {baseUrl = config.partnerBaseUrl, apiKey = "dev-key", timeoutMicros = 10_000_000}
  manager <- newPartnerManager partner
  pure WorkerEnv {..}

-- | Run a tick every @seconds@ (or once, for cron-style invocation).
runForever :: Bool -> Int -> IO () -> IO ()
runForever once seconds tick
  | once = tick
  | otherwise = forever (tick >> threadDelay (seconds * 1_000_000))

logLine :: Text -> Text -> IO ()
logLine worker msg = do
  t <- getCurrentTime
  TIO.putStrLn (T.pack (show t) <> " [" <> worker <> "] " <> msg)
  hFlush stdout

paymentRef :: PaymentId -> Text
paymentRef = T.pack . show . fromSqlKey
