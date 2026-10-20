-- | Polls the partner for the status of in-flight payments.
module Treasury.Workers.Poll (runPollWorker, pollOnce) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException)
import Control.Monad (forM_)
import Data.Text qualified as T
import Database.Persist
import Treasury.Db (runDb)
import Treasury.Model
import Treasury.Notifications (paymentEvent)
import Treasury.Partner.Client (getPaymentStatus)
import Treasury.Partner.Types (PartnerStatus (..), StatusResponse (..))
import Treasury.Payments (getPayment, markFailed, transition)
import Treasury.Payments.Status (PaymentStatus (..))
import Treasury.Workers.Shared
import UnliftIO (try)

runPollWorker :: WorkerEnv -> Bool -> IO ()
runPollWorker env once = runForever once 5 (pollOnce env)

pollOnce :: WorkerEnv -> IO ()
pollOnce env = do
  inFlight <- runDb env.pool (selectList [PaymentStatus <-. [Submitted, PartnerAcked], PaymentPartnerRef !=. Nothing] [Asc PaymentUpdatedAt, LimitTo 100])
  forM_ inFlight $ \(Entity pid p) -> case p.partnerRef of
    Nothing -> pure ()
    Just ref -> do
      result <- withRetries 3 (getPaymentStatus env.partner env.manager ref)
      case result of
        Left err -> logLine "poll" ("payment " <> paymentRef pid <> ": could not fetch status: " <> T.pack (show err))
        Right st -> apply pid p st
  where
    apply pid p st = case (p.status, st.status) of
      (Submitted, Acknowledged) -> do
        runDb env.pool (transition pid PartnerAcked)
        notify pid "acknowledged"
      (Submitted, SettledByPartner) -> do
        runDb env.pool (transition pid PartnerAcked >> transition pid Settled)
        notify pid "settled"
      (PartnerAcked, SettledByPartner) -> do
        runDb env.pool (transition pid Settled)
        notify pid "settled"
      (_, Rejected) -> do
        runDb env.pool (markFailed pid (maybe "rejected by partner" ("rejected by partner: " <>) st.reason))
        notify pid "failed"
      (_, Returned) -> do
        -- A return after acknowledgement. We don't have a status for this
        -- yet, so record it as a failure; the ledger reversal is handled
        -- manually by ops for now.
        runDb env.pool (transition pid Failed >> update pid [PaymentFailureReason =. fmap ("returned: " <>) st.reason])
        notify pid "failed"
      _ -> pure ()
    notify pid event = do
      payment <- runDb env.pool (getPayment pid)
      runDb env.pool (paymentEvent event payment)
      logLine "poll" ("payment " <> paymentRef pid <> " -> " <> event)

-- | Retry with exponential backoff: 1s, 2s, 4s, ...
withRetries :: Int -> IO a -> IO (Either SomeException a)
withRetries n action = go 0
  where
    go attempt = do
      r <- try action
      case r of
        Right a -> pure (Right a)
        Left e
          | attempt + 1 >= n -> pure (Left e)
          | otherwise -> threadDelay (2 ^ attempt * 1_000_000) >> go (attempt + 1)
