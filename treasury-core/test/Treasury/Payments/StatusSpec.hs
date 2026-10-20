module Treasury.Payments.StatusSpec (spec) where

import Test.Hspec
import Treasury.Payments.Status

spec :: Spec
spec = do
  describe "canTransition" $ do
    it "allows the happy path" $ do
      canTransition Initiated Submitted `shouldBe` True
      canTransition Submitted PartnerAcked `shouldBe` True
      canTransition PartnerAcked Settled `shouldBe` True
    it "never leaves a terminal state" $
      sequence_
        [ canTransition from to `shouldBe` False
        | from <- [minBound .. maxBound],
          isTerminal from,
          to <- [minBound .. maxBound]
        ]
    it "only allows cancellation before submission" $
      [from | from <- [minBound .. maxBound], canTransition from Cancelled] `shouldBe` [Initiated]
