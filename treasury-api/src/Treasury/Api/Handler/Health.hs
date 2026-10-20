module Treasury.Api.Handler.Health (getHealthR) where

import Data.Aeson (Value, object, (.=))
import Data.Text (Text)
import Database.Persist (Filter, count)
import Treasury.Api.Foundation
import Treasury.Model (Business)
import Yesod.Core (returnJson)

getHealthR :: Handler Value
getHealthR = do
  businesses <- db (count ([] :: [Filter Business]))
  returnJson (object ["status" .= ("ok" :: Text), "businesses" .= businesses])
