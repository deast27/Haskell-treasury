module Treasury.Api.PaymentsSpec (spec) where

import Data.Aeson (Value, object, (.=))
import Data.ByteString.Char8 qualified as BS8
import Data.Maybe (fromJust)
import Data.Text (Text)
import Network.HTTP.Types (methodPost)
import Test.Hspec
import Test.Hspec.Wai
import Treasury.Api.TestSupport

spec :: Spec
spec = withApp $ do
  describe "GET /health" $
    it "responds ok" $
      get "/health" `shouldRespondWith` 200

  describe "POST /payments" $ do
    it "reserves funds, is idempotent, and can be cancelled" $ do
      aid <- fundedAccount 100000
      let key = [("Idempotency-Key", "k-1")]
      created <- postJsonWith "/payments" key (payment aid 25000)
      pure created `shouldRespondWith` 201
      let pid = fromJust (bodyField "id" created) :: Int
      liftIO (bodyField "status" created `shouldBe` Just ("Initiated" :: Text))

      account <- get (accountPath aid)
      liftIO (bodyField "balance" account `shouldBe` Just (100000 - 25000 - 50 :: Int))

      replay <- postJsonWith "/payments" key (payment aid 25000)
      liftIO (bodyField "id" replay `shouldBe` Just pid)

      postJsonWith "/payments" key (payment aid 26000) `shouldRespondWith` 409

      cancelled <- request methodPost (BS8.pack ("/payments/" <> show pid <> "/cancel")) [] ""
      pure cancelled `shouldRespondWith` 200
      liftIO (bodyField "status" cancelled `shouldBe` Just ("Cancelled" :: Text))
      restored <- get (accountPath aid)
      liftIO (bodyField "balance" restored `shouldBe` Just (100000 :: Int))

      request methodPost (BS8.pack ("/payments/" <> show pid <> "/cancel")) [] "" `shouldRespondWith` 409

    it "rejects payments the account cannot cover" $ do
      aid <- fundedAccount 1000
      postJsonWith "/payments" [("Idempotency-Key", "k-2")] (payment aid 5000) `shouldRespondWith` 402

    it "requires an idempotency key" $ do
      aid <- fundedAccount 100000
      postJson "/payments" (payment aid 100) `shouldRespondWith` 400

fundedAccount :: Int -> WaiSession st Int
fundedAccount amount = do
  business <- postJson "/businesses" (object ["name" .= ("Acme Robotics" :: Text)])
  let bid = fromJust (bodyField "id" business) :: Int
  account <- postJson "/accounts" (object ["businessId" .= bid, "name" .= ("Operating" :: Text)])
  let aid = fromJust (bodyField "id" account) :: Int
  _ <- postJson (accountPath aid <> "/deposits") (object ["amount" .= amount, "description" .= ("seed" :: Text)])
  pure aid

accountPath :: Int -> BS8.ByteString
accountPath aid = BS8.pack ("/accounts/" <> show aid)

payment :: Int -> Int -> Value
payment aid amount =
  object
    [ "accountId" .= aid,
      "rail" .= ("Ach" :: Text),
      "amount" .= amount,
      "counterpartyName" .= ("Northwind Supplies" :: Text),
      "counterpartyRouting" .= ("021000021" :: Text),
      "counterpartyAccount" .= ("000123456789" :: Text),
      "memo" .= ("Invoice 1042" :: Text)
    ]
