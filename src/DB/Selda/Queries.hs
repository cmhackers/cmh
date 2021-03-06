module DB.Selda.Queries where

import           Control.Monad.Catch
import           Control.Monad.Except
import           DB.Selda.CMModels
import qualified DB.Selda.CMModels         as CMM
import           Data.Fixed                (HasResolution (resolution), Pico)
import           Data.String.Conv          (toS)
import qualified Data.Text                 as Text
import           Data.Time
import           Database.Selda            hiding (Group)
import qualified Database.Selda            as Selda
import           Database.Selda.Backend
import           Database.Selda.Debug
import           Database.Selda.Nullable
import           Database.Selda.PostgreSQL (PG)
import qualified Database.Selda.Unsafe     as SeldaUnsafe
import qualified Err
import           Relude                    hiding (group, id)
import           Types                     (ContactInfo (..), EventInfo (..),
                                            MatchInfo (..))
import           Util.Crypto               (genRandomBS, getRandTxt,
                                            makeDjangoPassword)

-- CREATE TABLES
initDatabase :: SeldaM PG ()
initDatabase  = do
  tryCreateTable org
  tryCreateTable CMM.league
  tryCreateTable user
  tryCreateTable group
  tryCreateTable player
  tryCreateTable event
  tryCreateTable eventrsvp
  tryCreateTable resetToken

mkUTCTime ::
  (Integer, Int, Int) ->
  (Int, Int, Pico) ->
  UTCTime
mkUTCTime (year, mon, day) (hour, min, sec) =
  UTCTime
    (fromGregorian year mon day)
    (timeOfDayToTime (TimeOfDay hour min sec))

getStartOfYear :: IO Day
getStartOfYear = do
  -- Get curr time we can query future events
  now <- liftIO getCurrentTime
  let (year, month, day) = toGregorian $ utctDay now
  let startOfYear = mkUTCTime (year, 1, 1) (0,0,0)
  return $ utctDay startOfYear


--------------------
-- QUERIES -
--------------------
getUser :: Text -> Query s (Row s User)
getUser username = do
  u <- select user
  restrict (u ! #username .== literal username)
  pure u

-- Not sure if there is a better way to get around the type checker
-- issues. This seems to work
seldaMaybeTextToLower :: Col s (Maybe Text) -> Col s (Maybe Text)
seldaMaybeTextToLower = SeldaUnsafe.fun "LOWER"

getUserByEmail :: Text -> Query s (Row s User)
getUserByEmail email = do
  let lcEmail = Text.toLower email
  u <- select user
  restrict (seldaMaybeTextToLower ( u ! #email) .== literal (Just lcEmail))
  pure u

insertResetTokenQ :: Text -> ID User -> SeldaM PG (ID ResetToken)
insertResetTokenQ token uid = do
  currTime <- liftIO getCurrentTime
  let oneDay = 24 * 60 * 60
  let ts = addUTCTime oneDay currTime
  insertWithPK resetToken [ResetToken token uid ts]

insertUserQ :: User -> SeldaM PG (ID User)
insertUserQ u =
  insertWithPK user [u]

insertUser :: SeldaConnection PG -> User -> IO (ID User)
insertUser conn u =
  runSeldaT (insertUserQ u) conn

insertPlayerQ :: Player -> SeldaM PG (ID Player)
insertPlayerQ p =
  insertWithPK player [p]

insertPlayer :: SeldaConnection PG -> Player -> IO (ID Player)
insertPlayer conn p =
  runSeldaT (insertPlayerQ p) conn

insertUserPlayerQ :: User -> SeldaM PG (ID User)
insertUserPlayerQ u = do
  uid <- insertUserQ u
  let p = Player def uid Nothing Nothing Nothing Nothing Nothing
  insertPlayerQ p
  pure uid

insertUserPlayer :: SeldaConnection PG -> User -> IO (ID User)
insertUserPlayer conn u =
  runSeldaT (transaction $ insertUserPlayerQ u) conn




allUsers :: Query s (Row s User)
allUsers = select user

allPlayers :: Query s (Row s Player)
allPlayers = select player

-- Join users and players

allUsersPlayers :: Query s (Row s User :*: Row s Player)
allUsersPlayers = do

  -- Restrict to active users
  u <- select user `suchThat` (\u ->
      u ! #is_active .== literal True
    )

  p <- select player
  restrict (u ! #id .== p ! #user_id)

  -- Order by first_name, then last_name.
  -- Selda sorts by later one first.
  order (u ! #last_name) ascending
  order (u ! #first_name) ascending
  return (u :*: p)


getPlayerByUsername :: Text -> Query s  (Row s Player)
getPlayerByUsername username = do
  (u :*: p) <- allUsersPlayers
  restrict (u ! #username .== literal username)
  return p


userInfo :: Text -> Query s (Row s User :*: Row s Player)
userInfo thisUser = do
  u :*: p <- allUsersPlayers
  restrict (u ! #username .== literal thisUser)
  return (u :*: p)

maybeHash :: Maybe Text -> IO (Maybe Text )
maybeHash mp = do
  case mp of
    Nothing -> return Nothing
    Just p ->  do
      h <- makeDjangoPassword p
      return $ Just h

updateUserInfo :: ContactInfo -> SeldaM PG ()
updateUserInfo ci = do
  let mpswd = password (ci::ContactInfo)
  hash <- liftIO $ maybeHash mpswd

  update_ user (\u -> u ! #username .== literal (username (ci::ContactInfo)) )
               (\u -> u `with` [
                 #first_name := literal (firstName ci),
                 #last_name := literal (lastName ci),
                 #email := literal (Just $ email (ci::ContactInfo)),
                 #password := maybe (u ! #password) literal hash
               ])
updatePlayerInfo :: ContactInfo -> SeldaM PG ()
updatePlayerInfo ci = do
  [u] <- query $ getUser (username (ci::ContactInfo))
  update_ player (\p -> p ! #user_id .== literal (id (u::User)) )
               (\u -> u `with` [
                 #mobile_phone := literal (Just $ mobilePhone ci),
                 #home_phone := literal (Just $ homePhone ci),
                 #work_phone := literal (Just $ workPhone ci)
               ])
updateProfile :: ContactInfo -> SeldaM PG ()
updateProfile ci = do
  transaction $ do
    updateUserInfo ci
    updatePlayerInfo ci

-- PASSWORD RESET

createResetSecret :: Text -> SeldaM PG (Maybe Text)
createResetSecret email = do
  mu <- query $ getUserByEmail email
  case mu of
    [u] -> do
      tokenBs <- liftIO  genRandomBS
      let token = toS tokenBs
      insertResetTokenQ (toS token) (id (u::User))
      return $ Just token
    [] -> return Nothing

cleanupResetTokens :: SeldaM PG ()
cleanupResetTokens = do
  currTime <- liftIO getCurrentTime
  deleteFrom_ resetToken (\a -> a ! #expiration .< literal currTime)
  return ()

getUserFromResetToken :: Text -> Query s (Row s User)
getUserFromResetToken token = do
  t <- select resetToken
  u <- select user
  restrict (t ! #user_id .== u ! #id )
  restrict (t ! #token .== literal token)
  pure u


-- EVENT

getEventWithRsvps :: ID Event -> SeldaM s (Event, [EventRsvp :*: Text])
getEventWithRsvps eid = do
  le <- query $
    select event `suchThat` (\e -> e ! #id .== literal eid)
  case le of
    [] -> throwM $ DbError $ "Event " <> show eid <> " not found"
    [e] -> do
      subQueryRes <- query $ do
        rsvps <- select eventrsvp `suchThat` (\r -> r ! #event_id .== literal eid)
        p <- innerJoin (\p -> rsvps ! #player_id .== p ! #id) (select player)
        u <- innerJoin (\u -> p ! #user_id .== u ! #id) (select user)
        order (u ! #username) ascending
        order (rsvps ! #response) ascending
        return (rsvps :*: u ! #username)
      return (e, subQueryRes)
  -- throwM $ DbError "getEventWithRsvps should never reach this line"

getRelevantEvents :: Text -> SeldaM s [Event :*: Maybe EventRsvp]
getRelevantEvents username = do
  -- Get curr time we can query future events
  now <- liftIO getCurrentTime
  -- let (sql, params) = compile  $ myQuery now
  -- liftIO $ print "-------- SQL join query -----------\n"
  -- liftIO $ putStrLn $ toS sql
  query $ myQuery now
  where
    myQuery ts = do
      u <- select user `suchThat` (\u -> u ! #username .== literal username)
      -- Get player row
      p <- innerJoin (\p -> p ! #user_id .== u ! #id) (select player)
      -- Get events
      e <- select event `suchThat` (\e -> e ! #date .>= literal ts)

      -- Join eventrsvp to get this user's RSVP
      mrsvp <- leftJoin (\er ->
          er ! #event_id .== e ! #id .&&
          er ! #player_id .== p ! #id
        ) (select eventrsvp)

      -- Left outer join registrations so we can filter irrelevant events
      r <- leftJoin (\reg -> e ?! #league_id .== (reg ?! #league_id)) $
            getRegistrationsByUsername username
      -- Filter to get either global (no league_id set) events or
      -- events for leagues to which this user is registered
      restrict ( isNull (e ! #league_id ) .||
                  (e ?! #league_id .== (r ?! #league_id)))
      --
      order (e ! #date) ascending
      return (e :*: mrsvp)


insertEvent :: Event -> SeldaM s (ID Event)
insertEvent evt = do
  insertWithPK event [evt]

updateEvent :: Event -> SeldaM s ()
updateEvent evt = do
  update_ event (\e -> e ! #id .== literal  (CMM.id (evt::CMM.Event))) (
    \e -> e `with` [
          #date := literal (date (evt::Event))
        , #name :=  literal (name (evt::Event))
        , #org_id :=  literal (org_id (evt::Event))
        , #event_type := literal (event_type (evt::Event))
        , #comment :=  literal (comment (evt::Event))
        , #always_show :=  literal (always_show (evt::Event))
        , #league_id :=  literal (league_id (evt::Event))
      ]
     )


-- EVENTRSVP

getEventRsvps :: ID Event -> SeldaM s [EventRsvp]
getEventRsvps eid = query $
    select eventrsvp `suchThat` (\e -> e ! #event_id .== literal eid)

recordEventRsvp :: EventRsvp -> SeldaM s ()
recordEventRsvp er = transaction $ do
  deleteFrom_ eventrsvp (\e ->
    e ! #event_id .== literal ( event_id er) .&&
    e ! #player_id .== literal (player_id (er::EventRsvp))
    )
  insert_ eventrsvp [er]

-- REGISTRATION

getRegistrationsByUsername :: Text -> Query s  (Row s Registration)
getRegistrationsByUsername username = do
  (u :*: p) <- allUsersPlayers
  restrict (u ! #username .== literal username)
  r <- select registration
  restrict (r ! #player_id .== p ! #id)
  return r


-- MATCH

getMatches :: Text -> SeldaM s [ Match :*: Maybe Text :*: Maybe Text :*: Maybe Text :*: Maybe Text :*: Maybe Text]
getMatches username = do
  soy <- liftIO getStartOfYear
  query $ do
    p <- getPlayerByUsername username
    m <- select match `suchThat` (\m1 -> m1 ! #date .>= literal soy)
    restrict (
        m ! #home_player1_id .== p ! #id .||
        m ! #away_player1_id .== p ! #id .||
        ifNull (literal $ toId 0) (m ! #home_player2_id) .== p ! #id .||
        ifNull (literal $ toId 0) (m ! #away_player2_id) .== p ! #id
      )
    l <- leftJoin (
        \l -> l ! #id .== m ! #league_id
      ) $ select CMM.league
    h1u :*: h1p <- leftJoin (
       \(u :*: p) -> m ! #home_player1_id .== p ! #id
      ) allUsersPlayers
    h2u :*: h2p <- leftJoin (
        \(u :*: p) -> ifNull (literal $ toId 0) (m ! #home_player2_id) .== p ! #id
      ) allUsersPlayers
    a1u :*: a1p <- leftJoin (
        \(u :*: p) -> m ! #away_player1_id .== p ! #id
      ) allUsersPlayers
    a2u :*: a2p <- leftJoin (
        \(u :*: p) -> ifNull (literal $ toId 0) (m ! #away_player2_id) .== p ! #id
      ) allUsersPlayers
    order (m ! #match_num) ascending
    order (m ! #round_num) ascending
    order (m ! #league_id) ascending
    order (m ! #date) ascending
    return  $ m :*: (l ? #abbrev ) :*: (h1u ? #username) :*: (h2u ? #username) :*: (a1u ? #username) :*: (a2u ? #username)


updateMatch :: Match -> SeldaM s ()
updateMatch mtch = do
  update_ match (\m -> m ! #id .== literal  (CMM.id (mtch::CMM.Match))) (
    \e -> e `with` [
          #score := literal (score (mtch::Match))
        , #home_won := literal (home_won (mtch::Match))
      ]
     )

