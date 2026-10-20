-- | Nightly reconciliation against the partner's settlement file.
--
-- Also sweeps payments that have been in flight for too long.
module Treasury.Workers.Reconcile (runReconcileWorker, reconcileOnce) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, unless)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (addUTCTime, utctDay)
import Database.Persist
import Treasury.Db (now, runDb)
import Treasury.Errors (HttpError (..))
import Treasury.Model
import Treasury.Notifications (paymentEvent)
import Treasury.Partner.Client (listSettlements)
import Treasury.Partner.Types (SettlementRecord (..))
import Treasury.Payments (getPayment, markFailed)
import Treasury.Payments.Status (PaymentStatus (..))
import Treasury.Workers.Shared
import UnliftIO (throwIO, try)

-- | Payments that have not left 'Submitted' within this window are abandoned.
submissionTimeoutSeconds :: Int
submissionTimeoutSeconds = 24 * 60 * 60

runReconcileWorker :: WorkerEnv -> Bool -> IO ()
runReconcileWorker env once = runForever once (60 * 60) (reconcileOnce env)

reconcileOnce :: WorkerEnv -> IO ()
reconcileOnce env = do
  t <- now
  -- 1. Partner settlement file vs our ledger
  settlementsOrErr <- try (listSettlements env.partner env.manager (utctDay t))
  settlements <- case settlementsOrErr of
    Right s -> pure s
    Left (HttpError 502 _) -> do
      -- partner file not ready yet; try again shortly
      logLine "reconcile" "settlement file unavailable (502), retrying in 30s"
      threadDelay 30_000_000
      listSettlements env.partner env.manager (utctDay t)
    Left (HttpError 429 _) -> do
      threadDelay 60_000_000
      listSettlements env.partner env.manager (utctDay t)
    Left e -> throwIO e
  settled <- runDb env.pool (selectList [PaymentStatus ==. Settled] [])
  let ours = Set.fromList [ref | Entity _ p <- settled, Just ref <- [p.partnerRef]]
      theirs = Set.fromList [s.partnerRef | s <- settlements]
  forM_ (Set.toList (Set.difference theirs ours)) $ \ref ->
    logLine "reconcile" ("MISMATCH: partner settled " <> ref <> " but we have no settled payment for it")
  forM_ (Set.toList (Set.difference ours theirs)) $ \ref ->
    logLine "reconcile" ("MISMATCH: we show " <> ref <> " settled but it is missing from the partner file")
  unless (null settlements) $
    logLine "reconcile" ("checked " <> T.pack (show (length settlements)) <> " settlements")

  -- 2. Sweep payments stuck in Submitted
  let cutoff = addUTCTime (negate (fromIntegral submissionTimeoutSeconds)) t
  stuck <- runDb env.pool (selectList [PaymentStatus ==. Submitted, PaymentUpdatedAt <. cutoff] [])
  forM_ stuck $ \(Entity pid _) -> do
    runDb env.pool (markFailed pid "timed out waiting for partner acknowledgement")
    payment <- runDb env.pool (getPayment pid)
    runDb env.pool (paymentEvent "failed" payment)
    logLine "reconcile" ("payment " <> paymentRef pid <> " timed out")
