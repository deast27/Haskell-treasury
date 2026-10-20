-- | Properties of the double-entry ledger.
--
-- The pure properties run everywhere; the ones that post journals need a
-- database (@CORE_TEST_DATABASE_URL@, defaulting to the @treasury_core_test@
-- database that @pg-start@ creates) and truncate it before every generated
-- case. It is deliberately not the API suite's @treasury_test@: @cabal test
-- all@ runs the two suites concurrently and both truncate between examples.
module Treasury.LedgerSpec (spec) where

import Data.ByteString.Char8 qualified as BS8
import Data.List (sort)
import Data.Maybe (fromMaybe)
import Database.Persist
import Database.Persist.Sql (rawExecute)
import System.Environment (lookupEnv)
import Test.Hspec
import Test.QuickCheck
import Treasury.Db (Db, DbPool, mkPool, now, runDb, runMigrations)
import Treasury.Errors (HttpError (..))
import Treasury.Ledger
import Treasury.Model
import Treasury.Money (Money)
import Treasury.Payments (NewPayment (..), cancelPayment, initiatePayment)
import Treasury.Payments.Status (PaymentStatus (..), Rail (..))
import UnliftIO (try)

spec :: Spec
spec = do
  describe "splitFee" $ do
    it "is conservative: the two shares sum to exactly the fee" $
      property $ \(NonNegative fee) ->
        let (ours, theirs) = splitFee fee
         in ours + theirs === fee
    it "never hands out a negative share" $
      property $ \(NonNegative fee) ->
        let (ours, theirs) = splitFee fee
         in ours >= 0 .&&. theirs >= 0

  beforeAll connect $ do
    describe "postJournal" $ do
      it "posts every balanced journal with its debits equal to its credits" $ \pool ->
        forAll genBalancedLines $ \ls -> ioProperty $ do
          resetDb pool
          runDb pool $ do
            accounts <- customerAccounts
            let entries = map (toLine accounts) ls
            jid <- postJournal "property" Nothing entries
            posted <- map entityVal <$> selectList [LedgerEntryJournalId ==. jid] []
            let debits = sum [e.amount | e <- posted, e.direction == Debit]
                credits = sum [e.amount | e <- posted, e.direction == Credit]
            pure $
              debits === credits
                .&&. sort [(e.accountId, e.direction, e.amount) | e <- posted]
                  === sort [(l.accountId, l.direction, l.amount) | l <- entries]

      it "rejects every unbalanced journal without writing anything" $ \pool ->
        forAll genUnbalancedLines $ \ls -> ioProperty $ do
          resetDb pool
          accounts <- runDb pool customerAccounts
          journalsBefore <- runDb pool (count ([] :: [Filter Journal]))
          result <- try (runDb pool (postJournal "property" Nothing (map (toLine accounts) ls)))
          journalsAfter <- runDb pool (count ([] :: [Filter Journal]))
          entries <- runDb pool (count ([] :: [Filter LedgerEntry]))
          pure $
            result === Left (HttpError 500 "unbalanced journal")
              .&&. journalsAfter === journalsBefore
              .&&. entries === 0

    describe "balance" $
      it "equals the fold over entriesFor" $ \pool ->
        forAll (resize 10 (listOf genBalancedLines)) $ \journals -> ioProperty $ do
          resetDb pool
          runDb pool $ do
            accounts <- customerAccounts
            mapM_ (postJournal "property" Nothing . map (toLine accounts)) journals
            conjoin
              <$> mapM
                ( \aid -> do
                    actual <- balance aid
                    entries <- entriesFor aid
                    pure (actual === sum [signed (entityVal e) | (_, e) <- entries])
                )
                accounts

    describe "initiatePayment then cancelPayment" $
      it "leaves every account balance where it started" $ \pool ->
        forAll genPaymentRequest $ \(rail, amount, headroom) -> ioProperty $ do
          resetDb pool
          (aid, opening) <- runDb pool $ do
            aid <- customerAccount
            -- Enough to cover the amount and any fee, with a little extra.
            _ <- fundAccount aid (amount + 10_000 + amount `div` 100 + headroom) "seed"
            (aid,) <$> snapshot aid
          payment <- runDb pool (initiatePayment "k-1" (newPayment aid rail amount))
          reserved <- runDb pool (snapshot aid)
          cancelled <- cancelPayment pool payment.entityKey
          closing <- runDb pool (snapshot aid)
          pure $
            cancelled.entityVal.status === Cancelled
              .&&. counterexample "funds were not reserved" (lookup Customer reserved < lookup Customer opening)
              .&&. counterexample "ledger drifted after cancellation" (closing === opening)

-- * Generators

-- | A ledger line against one of a small pool of customer accounts, by index.
data Line = Line Int Direction Money
  deriving stock (Show)

accountPoolSize :: Int
accountPoolSize = 4

genLine :: Gen Line
genLine =
  Line
    <$> choose (0, accountPoolSize - 1)
    <*> elements [Debit, Credit]
    <*> choose (1, 100_000_000)

-- | One or more random lines plus whatever line is needed to balance them.
genBalancedLines :: Gen [Line]
genBalancedLines = do
  ls <- listOf1 genLine
  let net = sum [signedLine l | l <- ls]
  pure $ case compare net 0 of
    EQ -> ls
    GT -> ls ++ [Line 0 Debit net]
    LT -> ls ++ [Line 0 Credit (negate net)]

-- | A balanced journal with one extra line, so debits and credits differ.
genUnbalancedLines :: Gen [Line]
genUnbalancedLines = do
  ls <- genBalancedLines
  extra <- genLine
  shuffle (extra : ls)

genPaymentRequest :: Gen (Rail, Money, Money)
genPaymentRequest =
  (,,)
    <$> elements [Ach, Wire]
    <*> choose (1, 10_000_000)
    <*> choose (0, 1_000)

-- * Helpers

signedLine :: Line -> Money
signedLine (Line _ Credit m) = m
signedLine (Line _ Debit m) = negate m

-- | Credits increase a customer balance, debits decrease it.
signed :: LedgerEntry -> Money
signed e = case e.direction of
  Credit -> e.amount
  Debit -> negate e.amount

toLine :: [AccountId] -> Line -> LedgerLine
toLine accounts (Line i d m) = LedgerLine (accounts !! i) d m

connect :: IO DbPool
connect = do
  url <- fromMaybe "postgresql://treasury@localhost:5433/treasury_core_test" <$> lookupEnv "CORE_TEST_DATABASE_URL"
  pool <- mkPool (BS8.pack url) 2
  runMigrations pool
  pure pool

resetDb :: DbPool -> IO ()
resetDb pool = runDb pool $ do
  rawExecute "TRUNCATE business, account, journal, ledger_entry, payment, webhook_outbox, audit_log RESTART IDENTITY CASCADE" []
  ensureSystemAccounts

customerAccount :: Db AccountId
customerAccount = do
  createdAt <- now
  bid <- insert Business {name = "Acme Robotics", createdAt}
  insert Account {businessId = Just bid, name = "Operating", kind = Customer, createdAt}

customerAccounts :: Db [AccountId]
customerAccounts = mapM (const customerAccount) [1 .. accountPoolSize]

-- | Balances of the customer account and the three system accounts.
snapshot :: AccountId -> Db [(AccountKind, Money)]
snapshot aid = do
  customer <- balance aid
  system <- mapM (\k -> (k,) <$> (systemAccount k >>= balance)) [Settlement, FeeRevenue, PartnerPayable]
  pure ((Customer, customer) : system)

newPayment :: AccountId -> Rail -> Money -> NewPayment
newPayment accountId rail amount =
  NewPayment
    { accountId,
      rail,
      amount,
      counterpartyName = "Northwind Supplies",
      counterpartyRouting = "021000021",
      counterpartyAccount = "000123456789",
      memo = Nothing
    }
