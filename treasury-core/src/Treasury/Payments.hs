-- | Outbound payments: initiation, cancellation and status transitions.
module Treasury.Payments
  ( NewPayment (..),
    initiatePayment,
    cancelPayment,
    transition,
    markFailed,
    feeFor,
    getPayment,
  )
where

import Control.Monad (when)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import Database.Persist
import Database.Persist.Sql (fromSqlKey)
import GHC.Generics (Generic)
import Treasury.Audit (Actor (..), audit)
import Treasury.Db (Db, DbPool, now, runDb)
import Treasury.Errors
import Treasury.Ledger
import Treasury.Model
import Treasury.Money (Money, formatMoney)
import Treasury.Notifications (paymentEvent)
import Treasury.Payments.Status

data NewPayment = NewPayment
  { accountId :: AccountId,
    rail :: Rail,
    amount :: Money,
    counterpartyName :: Text,
    counterpartyRouting :: Text,
    counterpartyAccount :: Text,
    memo :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Fee schedule: ACH is a flat 50 cents, wires are $25 plus 10 bps.
feeFor :: Rail -> Money -> Money
feeFor Ach _ = 50
feeFor Wire amount = 2500 + (amount * 10) `div` 10000

getPayment :: PaymentId -> Db (Entity Payment)
getPayment pid =
  get pid >>= \case
    Nothing -> notFound ("payment " <> T.pack (show (fromSqlKey pid)) <> " not found")
    Just p -> pure (Entity pid p)

-- | Create a payment, reserve the funds in the ledger and queue it for
-- submission. Safe to retry with the same idempotency key.
initiatePayment :: Text -> NewPayment -> Db (Entity Payment)
initiatePayment idempotencyKey np = do
  account <- get np.accountId >>= maybe (notFound "account not found") pure
  when (account.kind /= Customer) $
    unprocessable "payments can only be sent from customer accounts"
  when (np.amount <= 0) $ unprocessable "amount must be positive"
  existing <- getBy (UniqueIdempotencyKey np.accountId idempotencyKey)
  case existing of
    Just e@(Entity _ p)
      | samePayload p -> pure e
      | otherwise -> conflict "idempotency key was already used with a different payload"
    Nothing -> do
      let fee = feeFor np.rail np.amount
      available <- balance np.accountId
      when (available < np.amount + fee) $
        paymentRequired
          ( "insufficient funds: available "
              <> formatMoney available
              <> ", required "
              <> formatMoney (np.amount + fee)
          )
      t <- now
      pid <-
        insert
          Payment
            { accountId = np.accountId,
              rail = np.rail,
              amount = np.amount,
              fee,
              counterpartyName = np.counterpartyName,
              counterpartyRouting = np.counterpartyRouting,
              counterpartyAccount = np.counterpartyAccount,
              memo = np.memo,
              status = Initiated,
              idempotencyKey,
              partnerRef = Nothing,
              attempts = 0,
              lastAttemptAt = Nothing,
              failureReason = Nothing,
              createdAt = t,
              updatedAt = t
            }
      settlement <- systemAccount Settlement
      feeRevenue <- systemAccount FeeRevenue
      partnerPayable <- systemAccount PartnerPayable
      let (ours, theirs) = splitFee fee
      _ <-
        postJournal
          ("payment to " <> np.counterpartyName)
          (Just pid)
          [ LedgerLine np.accountId Debit (np.amount + fee),
            LedgerLine settlement Credit np.amount,
            LedgerLine feeRevenue Credit ours,
            LedgerLine partnerPayable Credit theirs
          ]
      audit (Actor "api") "payment.initiated" "payment" (T.pack (show (fromSqlKey pid)))
      p <- getPayment pid
      paymentEvent "initiated" p
      pure p
  where
    samePayload p =
      p.amount == np.amount
        && p.rail == np.rail
        && p.counterpartyAccount == np.counterpartyAccount
        && p.counterpartyRouting == np.counterpartyRouting

-- | Cancel a payment that has not been submitted to the partner yet and
-- release the reserved funds.
cancelPayment :: DbPool -> PaymentId -> IO (Entity Payment)
cancelPayment pool pid = do
  p <- runDb pool $ do
    Entity _ p <- getPayment pid
    when (p.status /= Initiated) $
      conflict ("cannot cancel a payment in status " <> statusText p.status)
    transition pid Cancelled
    reverseReservation pid p
    audit (Actor "api") "payment.cancelled" "payment" (T.pack (show (fromSqlKey pid)))
    getPayment pid
  -- Customer notification goes out once the cancellation is committed.
  runDb pool (paymentEvent "cancelled" p)
  pure p

reverseReservation :: PaymentId -> Payment -> Db ()
reverseReservation pid p = do
  settlement <- systemAccount Settlement
  feeRevenue <- systemAccount FeeRevenue
  partnerPayable <- systemAccount PartnerPayable
  let (ours, theirs) = splitFee p.fee
  _ <-
    postJournal
      ("reversal: payment to " <> p.counterpartyName)
      (Just pid)
      [ LedgerLine p.accountId Credit (p.amount + p.fee),
        LedgerLine settlement Debit p.amount,
        LedgerLine feeRevenue Debit ours,
        LedgerLine partnerPayable Debit theirs
      ]
  pure ()

-- | Move a payment to a new status, enforcing the lifecycle.
transition :: PaymentId -> PaymentStatus -> Db ()
transition pid to = do
  Entity _ p <- getPayment pid
  if canTransition p.status to
    then do
      t <- now
      update pid [PaymentStatus =. to, PaymentUpdatedAt =. t]
    else conflict ("illegal transition " <> statusText p.status <> " -> " <> statusText to)

markFailed :: PaymentId -> Text -> Db ()
markFailed pid reason = do
  Entity _ p <- getPayment pid
  transition pid Failed
  update pid [PaymentFailureReason =. Just reason]
  reverseReservation pid p
