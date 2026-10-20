module Treasury.Api.Handler.Payments
  ( postPaymentsR,
    getPaymentR,
    postPaymentCancelR,
  )
where

import Data.Text.Encoding qualified as TE
import Database.Persist (entityIdToJSON)
import Network.HTTP.Types (status201)
import Treasury.Api.Foundation
import Treasury.Errors (throwHttp)
import Treasury.Model (PaymentId)
import Treasury.Payments (cancelPayment, getPayment, initiatePayment)
import Yesod.Core

postPaymentsR :: Handler Value
postPaymentsR = do
  key <- lookupHeader "Idempotency-Key" >>= maybe (throwHttp 400 "Idempotency-Key header is required") (pure . TE.decodeUtf8)
  newPayment <- requireCheckJsonBody
  payment <- db (initiatePayment key newPayment)
  sendStatusJSON status201 (entityIdToJSON payment)

getPaymentR :: PaymentId -> Handler Value
getPaymentR pid = entityIdToJSON <$> db (getPayment pid)

postPaymentCancelR :: PaymentId -> Handler Value
postPaymentCancelR pid = do
  app <- getYesod
  entityIdToJSON <$> liftIO (cancelPayment app.appPool pid)
