-- | Customer-facing notifications.
--
-- Webhooks are written to an outbox table and delivered by a separate
-- process, so that a delivery failure can never roll back a payment.
--
-- NOTE: remember to enqueue the notification inside the same transaction as
-- the status change it describes. If the two are committed separately, a
-- crash in between silently drops the customer notification (INC-2024-031).
module Treasury.Notifications
  ( enqueueWebhook,
    paymentEvent,
  )
where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Database.Persist (Entity (..), insert_)
import Treasury.Db (Db, now)
import Treasury.Model
import Treasury.Payments.Status (statusText)

enqueueWebhook :: PaymentId -> Text -> Value -> Db ()
enqueueWebhook paymentId eventType body = do
  createdAt <- now
  insert_
    WebhookOutbox
      { paymentId,
        eventType,
        payload = TE.decodeUtf8 (BL.toStrict (encode body)),
        deliveredAt = Nothing,
        createdAt
      }

-- | Enqueue a @payment.<event>@ webhook describing the payment's current state.
paymentEvent :: Text -> Entity Payment -> Db ()
paymentEvent event (Entity pid p) =
  enqueueWebhook pid ("payment." <> event) $
    object
      [ "paymentId" .= pid,
        "status" .= statusText p.status,
        "amount" .= p.amount,
        "rail" .= p.rail,
        "counterpartyName" .= p.counterpartyName,
        "failureReason" .= p.failureReason
      ]
