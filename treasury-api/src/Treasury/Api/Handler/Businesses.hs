module Treasury.Api.Handler.Businesses
  ( postBusinessesR,
    getBusinessR,
  )
where

import Data.Text (Text)
import Database.Persist
import GHC.Generics (Generic)
import Network.HTTP.Types (status201)
import Treasury.Api.Foundation
import Treasury.Db (now)
import Treasury.Errors (notFound)
import Treasury.Model
import Yesod.Core hiding (notFound)

newtype NewBusiness = NewBusiness {name :: Text}
  deriving stock (Generic)
  deriving anyclass (FromJSON)

postBusinessesR :: Handler Value
postBusinessesR = do
  NewBusiness {name} <- requireCheckJsonBody
  createdAt <- now
  business <- db (insertEntity Business {name, createdAt})
  sendStatusJSON status201 (entityIdToJSON business)

getBusinessR :: BusinessId -> Handler Value
getBusinessR bid = do
  business <- db (get bid) >>= maybe (notFound "business not found") pure
  returnJson (entityIdToJSON (Entity bid business))
