-- | Double-entry ledger.
--
-- Every movement of money is a 'Journal' with two or more 'LedgerEntry'
-- rows whose debits and credits balance. Customer accounts are liabilities:
-- a credit increases what we owe the customer, a debit decreases it.
module Treasury.Ledger
  ( LedgerLine (..),
    postJournal,
    balance,
    splitFee,
    systemAccount,
    ensureSystemAccounts,
    fundAccount,
    entriesFor,
  )
where

import Control.Monad (forM_, unless)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Database.Esqueleto.Experimental
import Database.Persist qualified as P
import Treasury.Db (Db, now)
import Treasury.Errors (throwHttp)
import Treasury.Model
import Treasury.Money (Money, percentOf)

data LedgerLine = LedgerLine
  { accountId :: AccountId,
    direction :: Direction,
    amount :: Money
  }
  deriving stock (Show, Eq)

-- | Post a balanced journal. Throws if debits and credits differ.
postJournal :: Text -> Maybe PaymentId -> [LedgerLine] -> Db JournalId
postJournal description paymentId entries = do
  let debits = sum [l.amount | l <- entries, l.direction == Debit]
      credits = sum [l.amount | l <- entries, l.direction == Credit]
  unless (debits == credits) $
    throwHttp 500 "unbalanced journal"
  createdAt <- now
  journalId <- insert Journal {description, paymentId, createdAt}
  forM_ entries $ \LedgerLine {..} ->
    insert_ LedgerEntry {journalId, accountId, direction, amount}
  pure journalId

-- | Current balance of a customer account (credits minus debits).
balance :: AccountId -> Db Money
balance aid = do
  rows <- select $ do
    e <- from $ table @LedgerEntry
    where_ (e ^. LedgerEntryAccountId ==. val aid)
    groupBy (e ^. LedgerEntryDirection)
    pure (e ^. LedgerEntryDirection, sum_ (e ^. LedgerEntryAmount))
  let total d = sum [fromMaybe 0 s | (Value d', Value s) <- rows, d' == d]
  pure (total Credit - total Debit)

-- | Split a fee between us and the partner bank (70/30).
splitFee :: Money -> (Money, Money)
splitFee fee = (percentOf 7000 fee, percentOf 3000 fee)

systemAccount :: AccountKind -> Db AccountId
systemAccount kind = do
  existing <- P.selectFirst [AccountKind P.==. kind, AccountBusinessId P.==. Nothing] []
  case existing of
    Just (Entity aid _) -> pure aid
    Nothing -> do
      createdAt <- now
      insert Account {businessId = Nothing, name = systemName kind, kind, createdAt}
  where
    systemName = \case
      Settlement -> "Partner settlement clearing"
      FeeRevenue -> "Fee revenue"
      PartnerPayable -> "Partner fee payable"
      Customer -> "Unassigned customer account"

ensureSystemAccounts :: Db ()
ensureSystemAccounts = mapM_ systemAccount [Settlement, FeeRevenue, PartnerPayable]

-- | Record an incoming deposit into a customer account.
fundAccount :: AccountId -> Money -> Text -> Db JournalId
fundAccount aid amount description = do
  settlement <- systemAccount Settlement
  postJournal
    description
    Nothing
    [ LedgerLine settlement Debit amount,
      LedgerLine aid Credit amount
    ]

entriesFor :: AccountId -> Db [(Entity Journal, Entity LedgerEntry)]
entriesFor aid = select $ do
  (j :& e) <-
    from $
      table @Journal
        `innerJoin` table @LedgerEntry
          `on` (\(j :& e) -> j ^. JournalId ==. e ^. LedgerEntryJournalId)
  where_ (e ^. LedgerEntryAccountId ==. val aid)
  orderBy [desc (j ^. JournalCreatedAt)]
  pure (j, e)
