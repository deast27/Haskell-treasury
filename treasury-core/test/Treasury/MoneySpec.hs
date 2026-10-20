module Treasury.MoneySpec (spec) where

import Test.Hspec
import Test.QuickCheck
import Treasury.Money

spec :: Spec
spec = do
  describe "formatMoney" $ do
    it "groups thousands and pads cents" $
      formatMoney 123456789 `shouldBe` "$1,234,567.89"
    it "renders small amounts" $
      formatMoney 5 `shouldBe` "$0.05"
    it "renders negative amounts" $
      formatMoney (-100) `shouldBe` "-$1.00"
  describe "percentOf" $ do
    it "100% is the identity" $
      property $
        \(NonNegative n) -> percentOf 10000 n == n
    it "never exceeds the amount" $
      property $
        \(NonNegative n) (Positive bps) -> bps <= 10000 ==> percentOf bps n <= n
