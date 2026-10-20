-- | Monetary amounts.
--
-- All amounts are integer cents. Accounts are USD-only today, so the
-- currency is implied everywhere an amount is passed around.
module Treasury.Money
  ( Money,
    cents,
    toCents,
    formatMoney,
    percentOf,
  )
where

import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T
import Text.Printf (printf)

type Money = Int

cents :: Int -> Money
cents = id

toCents :: Money -> Int
toCents = id

-- | Render an amount as @$1,234.56@. Negative amounts render as @-$1.00@.
formatMoney :: Money -> Text
formatMoney m =
  let sign = if m < 0 then "-" else ""
      (dollars, cs) = abs m `divMod` 100
   in T.pack (sign <> "$" <> groupThousands (show dollars) <> printf ".%02d" cs)
  where
    groupThousands = reverse . intercalate "," . chunksOf3 . reverse
    chunksOf3 [] = []
    chunksOf3 xs = let (a, b) = splitAt 3 xs in a : chunksOf3 b

-- | Basis points of an amount, rounded down to the cent.
percentOf :: Int -> Money -> Money
percentOf bps amount = (amount * bps) `div` 10000
