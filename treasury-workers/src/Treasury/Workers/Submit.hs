-- | Submits newly initiated payments to the partner bank.
module Treasury.Workers.Submit (runSubmitWorker, submitOnce) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_)
import Data.Text qualified as T
import Database.Persist
import Treasury.Db (now, runDb)
import Treasury.Errors (HttpError (..))
import Treasury.Model
import Treasury.Notifications (paymentEvent)
import Treasury.Partner.Client (submitPayment)
import Treasury.Partner.Types (Receipt (..), Submission (..))
import Treasury.Payments (getPayment, markFailed, transition)
import Treasury.Payments.Status (PaymentStatus (..))
import Treasury.Workers.Shared
import UnliftIO (try)

maxAttempts :: Int
maxAttempts = 5

runSubmitWorker :: WorkerEnv -> Bool -> IO ()
runSubmitWorker env once = runForever once 5 (submitOnce env)

submitOnce :: WorkerEnv -> IO ()
submitOnce env = do
  pending <- runDb env.pool (selectList [PaymentStatus ==. Initiated, PaymentAttempts <. maxAttempts] [Asc PaymentCreatedAt, LimitTo 50])
  forM_ pending (submitOne env)

submitOne :: WorkerEnv -> Entity Payment -> IO ()
submitOne env (Entity pid p) = go 1
  where
    submission =
      Submission
        { clientRef = "treasury-" <> paymentRef pid,
          rail = T.toLower (T.pack (show p.rail)),
          amountCents = p.amount,
          counterpartyName = p.counterpartyName,
          counterpartyRouting = p.counterpartyRouting,
          counterpartyAccount = p.counterpartyAccount
        }
    go :: Int -> IO ()
    go tryNo = do
      t <- now
      runDb env.pool (update pid [PaymentAttempts +=. 1, PaymentLastAttemptAt =. Just t])
      result <- try (submitPayment env.partner env.manager submission)
      case result of
        Right receipt -> do
          submitted <- runDb env.pool $ do
            transition pid Submitted
            update pid [PaymentPartnerRef =. Just receipt.partnerRef]
            getPayment pid
          -- notify the customer now that the status is committed
          runDb env.pool (paymentEvent "submitted" submitted)
          logLine "submit" ("payment " <> paymentRef pid <> " submitted as " <> receipt.partnerRef)
        Left (HttpError code msg)
          -- 502/503/504: partner is having a moment, back off and try again
          | code `elem` [502, 503, 504] && tryNo < 3 -> do
              logLine "submit" ("payment " <> paymentRef pid <> " partner error " <> T.pack (show code) <> ", retrying")
              threadDelay (tryNo * 2_000_000)
              go (tryNo + 1)
          -- 409: the partner already has this clientRef; the poll worker will pick it up
          | code == 409 -> logLine "submit" ("payment " <> paymentRef pid <> " already known to partner, skipping")
          | code `elem` [502, 503, 504] -> logLine "submit" ("payment " <> paymentRef pid <> " giving up for now: " <> msg)
          | otherwise -> do
              runDb env.pool (markFailed pid ("partner rejected submission: " <> msg))
              failed <- runDb env.pool (getPayment pid)
              runDb env.pool (paymentEvent "failed" failed)
              logLine "submit" ("payment " <> paymentRef pid <> " failed: " <> msg)
