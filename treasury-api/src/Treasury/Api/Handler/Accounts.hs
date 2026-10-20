module Treasury.Api.Handler.Accounts
  ( postAccountsR,
    getAccountR,
    postAccountDepositsR,
    getAccountLedgerR,
  )
where

import Control.Monad (when)
import Data.Text (Text)
import Database.Persist
import GHC.Generics (Generic)
import Network.HTTP.Types (status201)
import Treasury.Api.Foundation
import Treasury.Db (Db, now)
import Treasury.Errors (notFound, unprocessable)
import Treasury.Ledger (balance, entriesFor, fundAccount)
import Treasury.Model
import Treasury.Money (formatMoney)
import Yesod.Core hiding (notFound)

data NewAccount = NewAccount
  { businessId :: BusinessId,
    name :: Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data Deposit = Deposit
  { amount :: Int,
    description :: Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

postAccountsR :: Handler Value
postAccountsR = do
  NewAccount {businessId, name} <- requireCheckJsonBody
  createdAt <- now
  account <- db $ do
    _ <- get businessId >>= maybe (notFound "business not found") pure
    insertEntity Account {businessId = Just businessId, name, kind = Customer, createdAt}
  sendStatusJSON status201 (entityIdToJSON account)

getAccountR :: AccountId -> Handler Value
getAccountR aid = do
  (account, available) <- db ((,) <$> getAccount aid <*> balance aid)
  returnJson (accountView (Entity aid account) available)

postAccountDepositsR :: AccountId -> Handler Value
postAccountDepositsR aid = do
  Deposit {amount, description} <- requireCheckJsonBody
  when (amount <= 0) $ unprocessable "deposit amount must be positive"
  (account, available) <- db $ do
    account <- getAccount aid
    _ <- fundAccount aid amount description
    (account,) <$> balance aid
  sendStatusJSON status201 (accountView (Entity aid account) available)

getAccountLedgerR :: AccountId -> Handler Value
getAccountLedgerR aid = do
  rows <- db (getAccount aid >> entriesFor aid)
  returnJson
    [ object
        [ "journalId" .= jid,
          "description" .= journal.description,
          "paymentId" .= journal.paymentId,
          "direction" .= entry.direction,
          "amount" .= entry.amount,
          "postedAt" .= journal.createdAt
        ]
    | (Entity jid journal, Entity _ entry) <- rows
    ]

getAccount :: AccountId -> Db Account
getAccount aid = get aid >>= maybe (notFound "account not found") pure

accountView :: Entity Account -> Int -> Value
accountView (Entity aid a) available =
  object
    [ "id" .= aid,
      "businessId" .= a.businessId,
      "name" .= a.name,
      "kind" .= a.kind,
      "balance" .= available,
      "balanceFormatted" .= formatMoney available,
      "createdAt" .= a.createdAt
    ]
