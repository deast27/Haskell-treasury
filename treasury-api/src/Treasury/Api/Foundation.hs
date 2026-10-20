{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-missing-export-lists #-}

-- | Yesod foundation type and routes.
module Treasury.Api.Foundation where

import Network.HTTP.Types (mkStatus)
import Treasury.Config (Config)
import Treasury.Db (Db, DbPool, runDb)
import Treasury.Errors (HttpError (..))
import Treasury.Model
import UnliftIO (catch)
import Yesod.Core

data App = App
  { appPool :: DbPool,
    appConfig :: Config
  }

mkYesodData
  "App"
  [parseRoutes|
/health                          HealthR          GET
/businesses                      BusinessesR      POST
/businesses/#BusinessId          BusinessR        GET
/accounts                        AccountsR        POST
/accounts/#AccountId             AccountR         GET
/accounts/#AccountId/deposits    AccountDepositsR POST
/accounts/#AccountId/ledger      AccountLedgerR   GET
/payments                        PaymentsR        POST
/payments/#PaymentId             PaymentR         GET
/payments/#PaymentId/cancel      PaymentCancelR   POST
|]

instance Yesod App where
  makeSessionBackend _ = pure Nothing

  -- Domain code raises 'HttpError'; translate it straight into a response.
  yesodMiddleware handler =
    defaultYesodMiddleware handler `catch` \(HttpError code msg) ->
      sendStatusJSON (mkStatus code "") (object ["error" .= msg])

  errorHandler err = do
    let (st, msg) = case err of
          NotFound -> (404, "not found")
          NotAuthenticated -> (401, "not authenticated")
          PermissionDenied m -> (403, m)
          InvalidArgs _ -> (400, "invalid arguments")
          BadMethod _ -> (405, "method not allowed")
          InternalError m -> (500, m)
    sendStatusJSON (mkStatus st "") (object ["error" .= msg])

-- | Run a database transaction from a handler.
db :: Db a -> Handler a
db action = do
  app <- getYesod
  liftIO (runDb app.appPool action)
