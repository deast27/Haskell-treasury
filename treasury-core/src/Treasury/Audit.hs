-- | Append-only audit trail. Regulators read this; keep it boring.
module Treasury.Audit
  ( Actor (..),
    audit,
  )
where

import Data.Text (Text)
import Database.Persist (insert_)
import Treasury.Db (Db, now)
import Treasury.Model

newtype Actor = Actor Text

audit :: Actor -> Text -> Text -> Text -> Db ()
audit (Actor actor) action subjectType subjectId = do
  createdAt <- now
  insert_ AuditLog {..}
