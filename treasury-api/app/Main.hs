module Main (main) where

import Control.Exception (bracket)
import Network.Wai.Handler.Warp (run)
import OpenTelemetry.Trace (initializeGlobalTracerProvider, shutdownTracerProvider)
import Treasury.Api.Application (makeApplication, makeFoundation)
import Treasury.Config (Config (..), loadConfig)

main :: IO ()
main = bracket initializeGlobalTracerProvider shutdownTracerProvider $ \_ -> do
  config <- loadConfig
  app <- makeFoundation config >>= makeApplication
  putStrLn ("treasury-api listening on :" <> show config.port)
  run config.port app
