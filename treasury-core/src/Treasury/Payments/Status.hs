{-# LANGUAGE TemplateHaskell #-}

-- | Payment lifecycle.
--
-- @
--   Initiated --> Submitted --> PartnerAcked --> Settled
--       |             |              |
--       v             v              v
--   Cancelled       Failed         Failed
-- @
module Treasury.Payments.Status
  ( PaymentStatus (..),
    Rail (..),
    canTransition,
    isTerminal,
    statusText,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Database.Persist.TH (derivePersistField)
import GHC.Generics (Generic)

data PaymentStatus
  = Initiated
  | Submitted
  | PartnerAcked
  | Settled
  | Failed
  | Cancelled
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (ToJSON, FromJSON)

derivePersistField "PaymentStatus"

data Rail = Ach | Wire
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (ToJSON, FromJSON)

derivePersistField "Rail"

canTransition :: PaymentStatus -> PaymentStatus -> Bool
canTransition from to = case (from, to) of
  (Initiated, Submitted) -> True
  (Initiated, Cancelled) -> True
  (Initiated, Failed) -> True
  (Submitted, PartnerAcked) -> True
  (Submitted, Failed) -> True
  (PartnerAcked, Settled) -> True
  (PartnerAcked, Failed) -> True
  _ -> False

isTerminal :: PaymentStatus -> Bool
isTerminal = \case
  Settled -> True
  Failed -> True
  Cancelled -> True
  _ -> False

statusText :: PaymentStatus -> Text
statusText = \case
  Initiated -> "initiated"
  Submitted -> "submitted"
  PartnerAcked -> "partner_acked"
  Settled -> "settled"
  Failed -> "failed"
  Cancelled -> "cancelled"
