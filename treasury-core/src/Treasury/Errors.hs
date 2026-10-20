-- | Errors raised by the treasury domain.
--
-- Handlers in the API catch 'HttpError' and send the status straight back to
-- the client, which is convenient because most of this code was written for
-- request handlers.
module Treasury.Errors
  ( HttpError (..),
    throwHttp,
    notFound,
    conflict,
    paymentRequired,
    badGateway,
    unprocessable,
  )
where

import Control.Exception (Exception)
import Data.Text (Text)
import UnliftIO (MonadIO, throwIO)

data HttpError = HttpError
  { status :: Int,
    message :: Text
  }
  deriving stock (Show, Eq)

instance Exception HttpError

throwHttp :: (MonadIO m) => Int -> Text -> m a
throwHttp s m = throwIO (HttpError s m)

notFound :: (MonadIO m) => Text -> m a
notFound = throwHttp 404

conflict :: (MonadIO m) => Text -> m a
conflict = throwHttp 409

paymentRequired :: (MonadIO m) => Text -> m a
paymentRequired = throwHttp 402

badGateway :: (MonadIO m) => Text -> m a
badGateway = throwHttp 502

unprocessable :: (MonadIO m) => Text -> m a
unprocessable = throwHttp 422
