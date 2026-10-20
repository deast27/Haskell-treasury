{-# LANGUAGE FieldSelectors #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-missing-export-lists #-}

-- | Persistent schema. Column types mirror the production database as it
-- exists today; see dev/migrations in the original service for history.
module Treasury.Model where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics (Generic)
import Treasury.Payments.Status (PaymentStatus, Rail)

data AccountKind
  = -- | A customer's operating account (liability to the customer).
    Customer
  | -- | Clearing account for funds in flight to/from the partner bank.
    Settlement
  | -- | Our share of payment fees.
    FeeRevenue
  | -- | The partner bank's share of payment fees, paid out monthly.
    PartnerPayable
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (ToJSON, FromJSON)

derivePersistField "AccountKind"

data Direction = Debit | Credit
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (ToJSON, FromJSON)

derivePersistField "Direction"

share
  [mkPersist sqlSettings {mpsFieldLabelModifier = \_entity field -> field}, mkMigrate "migrateAll"]
  [persistLowerCase|
Business json
    name Text
    createdAt UTCTime
    deriving Show Eq

Account json
    businessId BusinessId Maybe
    name Text
    kind AccountKind
    createdAt UTCTime
    deriving Show Eq

Journal json
    description Text
    paymentId PaymentId Maybe
    createdAt UTCTime
    deriving Show Eq

LedgerEntry json
    journalId JournalId
    accountId AccountId
    direction Direction
    amount Int
    deriving Show Eq

Payment json
    accountId AccountId
    rail Rail
    amount Int
    fee Int
    counterpartyName Text
    counterpartyRouting Text
    counterpartyAccount Text
    memo Text Maybe
    status PaymentStatus
    idempotencyKey Text
    partnerRef Text Maybe
    attempts Int
    lastAttemptAt UTCTime Maybe
    failureReason Text Maybe
    createdAt UTCTime
    updatedAt UTCTime
    UniqueIdempotencyKey accountId idempotencyKey
    deriving Show Eq

WebhookOutbox json
    paymentId PaymentId
    eventType Text
    payload Text
    deliveredAt UTCTime Maybe
    createdAt UTCTime
    deriving Show Eq

AuditLog json
    actor Text
    action Text
    subjectType Text
    subjectId Text
    createdAt UTCTime
    deriving Show Eq
|]
