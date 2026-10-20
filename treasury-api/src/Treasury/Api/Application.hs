{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Wires the foundation, handlers and middleware into a WAI application.
module Treasury.Api.Application
  ( makeApplication,
    makeFoundation,
  )
where

import Network.Wai (Application)
import Network.Wai.Middleware.RequestLogger (logStdout)
import OpenTelemetry.Instrumentation.Wai (newOpenTelemetryWaiMiddleware)
import Treasury.Api.Foundation
import Treasury.Api.Handler.Accounts
import Treasury.Api.Handler.Businesses
import Treasury.Api.Handler.Health
import Treasury.Api.Handler.Payments
import Treasury.Config (Config (..))
import Treasury.Db (mkPool, runDb, runMigrations)
import Treasury.Ledger (ensureSystemAccounts)
import Yesod.Core (mkYesodDispatch, toWaiAppPlain)

mkYesodDispatch "App" resourcesApp

makeFoundation :: Config -> IO App
makeFoundation config = do
  pool <- mkPool config.databaseUrl config.poolSize
  runMigrations pool
  runDb pool ensureSystemAccounts
  pure App {appPool = pool, appConfig = config}

makeApplication :: App -> IO Application
makeApplication app = do
  otel <- newOpenTelemetryWaiMiddleware
  otel . logStdout <$> toWaiAppPlain app
