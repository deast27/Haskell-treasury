-- | Database access.
module Treasury.Db
  ( Db,
    DbPool,
    mkPool,
    runDb,
    runMigrations,
    now,
  )
where

import Control.Monad.Logger (runStderrLoggingT)
import Data.ByteString (ByteString)
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist.Postgresql (ConnectionPool, SqlPersistT, createPostgresqlPool, runMigration, runSqlPool)
import Treasury.Model (migrateAll)
import UnliftIO (MonadIO, MonadUnliftIO, liftIO)

type Db = SqlPersistT IO

type DbPool = ConnectionPool

mkPool :: ByteString -> Int -> IO DbPool
mkPool url size = runStderrLoggingT (createPostgresqlPool url size)

-- | Run a database action in a single transaction.
runDb :: (MonadUnliftIO m) => DbPool -> SqlPersistT m a -> m a
runDb pool action = runSqlPool action pool

runMigrations :: DbPool -> IO ()
runMigrations pool = runDb pool (runMigration migrateAll)

now :: (MonadIO m) => m UTCTime
now = liftIO getCurrentTime
