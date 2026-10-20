module Main (main) where

import Options.Applicative
import Treasury.Config (loadConfig)
import Treasury.Workers.Poll (runPollWorker)
import Treasury.Workers.Reconcile (runReconcileWorker)
import Treasury.Workers.Shared (mkWorkerEnv)
import Treasury.Workers.Submit (runSubmitWorker)

data Command = Submit | Poll | Reconcile

data Opts = Opts
  { command :: Command,
    once :: Bool
  }

opts :: Parser Opts
opts =
  Opts
    <$> hsubparser
      ( command "submit" (info (pure Submit) (progDesc "Submit initiated payments to the partner"))
          <> command "poll" (info (pure Poll) (progDesc "Poll the partner for in-flight payment status"))
          <> command "reconcile" (info (pure Reconcile) (progDesc "Reconcile settlements and sweep stuck payments"))
      )
    <*> switch (long "once" <> help "Run a single tick and exit (for cron)")

main :: IO ()
main = do
  o <- execParser (info (opts <**> helper) (fullDesc <> progDesc "treasury background workers"))
  env <- loadConfig >>= mkWorkerEnv
  case o.command of
    Submit -> runSubmitWorker env o.once
    Poll -> runPollWorker env o.once
    Reconcile -> runReconcileWorker env o.once
