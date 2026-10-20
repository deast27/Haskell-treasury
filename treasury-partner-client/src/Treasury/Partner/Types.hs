-- | Wire types for the partner bank's payments API (v1).
module Treasury.Partner.Types
  ( PartnerConfig (..),
    Submission (..),
    Receipt (..),
    PartnerStatus (..),
    StatusResponse (..),
    SettlementRecord (..),
  )
where

import Data.Aeson
import Data.Text (Text)
import Data.Time (Day, UTCTime)
import GHC.Generics (Generic)

data PartnerConfig = PartnerConfig
  { baseUrl :: Text,
    apiKey :: Text,
    timeoutMicros :: Int
  }
  deriving stock (Show)

data Submission = Submission
  { clientRef :: Text,
    rail :: Text,
    amountCents :: Int,
    counterpartyName :: Text,
    counterpartyRouting :: Text,
    counterpartyAccount :: Text
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

data Receipt = Receipt
  { partnerRef :: Text,
    acceptedAt :: UTCTime
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Status values the partner documents. @returned@ means the receiving
-- bank bounced the payment after we had already been told it was accepted.
data PartnerStatus
  = Accepted
  | Acknowledged
  | SettledByPartner
  | Returned
  | Rejected
  deriving stock (Show, Eq, Generic)

instance ToJSON PartnerStatus where
  toJSON = \case
    Accepted -> "accepted"
    Acknowledged -> "acknowledged"
    SettledByPartner -> "settled"
    Returned -> "returned"
    Rejected -> "rejected"

instance FromJSON PartnerStatus where
  parseJSON = withText "PartnerStatus" $ \case
    "accepted" -> pure Accepted
    "acknowledged" -> pure Acknowledged
    "settled" -> pure SettledByPartner
    "returned" -> pure Returned
    "rejected" -> pure Rejected
    other -> fail ("unknown partner status: " <> show other)

data StatusResponse = StatusResponse
  { partnerRef :: Text,
    status :: PartnerStatus,
    reason :: Maybe Text,
    updatedAt :: UTCTime
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

data SettlementRecord = SettlementRecord
  { partnerRef :: Text,
    clientRef :: Text,
    amountCents :: Int,
    settledOn :: Day
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)
