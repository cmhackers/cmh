{-# LANGUAGE OverloadedStrings #-}

module Handlers.TennisHandler where

import           API.TennisApi              (TennisApi)
import           AppM
import           Control.Monad.Except       (MonadIO (..))
import           Control.Monad.Trans.Reader (asks)
import qualified DB.Selda.CMModels          as CMM
import qualified DB.Selda.Queries           as Query
import           Database.Selda             (Query, Row, SqlRow,
                                             SqlType (fromSql), def, fromId,
                                             query, toId, transaction,
                                             (:*:) ((:*:)))
import           Database.Selda.Backend     (runSeldaT)
import           Database.Selda.PostgreSQL  (PG)
import           Relude                     hiding (asks)

import           Err
-- import           Protolude                  (putText, threadDelay, toS, (&), undefined)
import qualified Data.Text                  as Text
import           Data.Time
import           Servant
import qualified Servant.Auth.Server        as SAS
import           Servant.Server             ()
import           Types                      (ContactInfo (..), EventInfo (..),
                                             EventRsvpInfo (..),
                                             UserData (email, username),
                                             getUserName, modUserName)
import           Util.Crypto

-- Servant Handlers

tennisHandler :: ServerT (TennisApi auths) AppM
tennisHandler =
  users
  :<|> getUser
  :<|> players
  :<|> updateProfile
  :<|> Handlers.TennisHandler.player
  :<|> events
  :<|> insertEvent
  :<|> updateEvent
  :<|> eventRsvps
  :<|> eventRsvp


-- Get data from database

users :: AppM [CMM.User]
users = dbQuery Query.allUsers

getUser :: Text -> AppM (Maybe CMM.User)
getUser un = do
  us <- dbQuery (Query.getUser un)
  pure $ case us of
    [u] -> pure u
    _   -> Nothing

playersHelper :: Query PG (Row PG CMM.User :*: Row PG CMM.Player) -> UserData -> AppM [ContactInfo]
playersHelper q _user = do
  conn <- asks dbConn
  res::[CMM.User :*: CMM.Player]  <- runSeldaT (query q) conn
  mapM (
    \(u :*: p) -> do
      -- u <- lift  u'
      -- p <- lift p'
      return $ ContactInfo
        (CMM.username (u::CMM.User))
        (CMM.first_name (u::CMM.User))
        (CMM.last_name (u::CMM.User))
        (Just $ CMM.password (u::CMM.User))
        (fromMaybe "" $ CMM.email (u::CMM.User))
        (fromMaybe "" $ CMM.mobile_phone (p::CMM.Player))
        (fromMaybe "" $ CMM.home_phone (p::CMM.Player))
        (fromMaybe "" $ CMM.work_phone (p::CMM.Player))
    ) res

players :: SAS.AuthResult UserData -> AppM [ContactInfo]
players (SAS.Authenticated _user) = playersHelper Query.allUsersPlayers  _user
players _ = forbidden " Pelase Login to see Contact info"

player :: SAS.AuthResult UserData -> Text -> AppM (Maybe ContactInfo)
player (SAS.Authenticated user) un = do
  res <- playersHelper (Query.userInfo un) user
  case res of
    [p] -> return $ Just p
    _   -> notFound $ "No user " <> un
player _ _ = forbidden " Pelase Login to see Contact info"

eventRsvpInfoFromDb:: CMM.EventRsvp -> EventRsvpInfo
eventRsvpInfoFromDb rsvp = EventRsvpInfo
  { eventId = fromId $ CMM.event_id (rsvp::CMM.EventRsvp)
  -- TODO Should this be a username instead of player_id?
  , playerId = fromId $ CMM.player_id (rsvp::CMM.EventRsvp)
  , response = CMM.response (rsvp::CMM.EventRsvp)
  , comment = CMM.comment (rsvp::CMM.EventRsvp)
  }

eventRsvpInfoToDb:: EventRsvpInfo -> CMM.EventRsvp
eventRsvpInfoToDb rsvp = CMM.EventRsvp
  { id = def
  , event_id = toId $ eventId (rsvp::EventRsvpInfo)
  , player_id = toId $ playerId (rsvp::EventRsvpInfo)
  , response = response (rsvp::EventRsvpInfo)
  , comment = comment (rsvp::EventRsvpInfo)
  }


eventFromDb :: CMM.Event :*: Maybe CMM.EventRsvp -> EventInfo
eventFromDb (dbEvt :*: rsvp) =
  EventInfo { eventId= Just $ fromId $ CMM.id (dbEvt:: CMM.Event)
            , date= CMM.date (dbEvt:: CMM.Event)
            , name= CMM.name (dbEvt:: CMM.Event)
            , eventType= CMM.event_type (dbEvt:: CMM.Event)
            , comment= CMM.comment (dbEvt:: CMM.Event)
            , alwaysShow= CMM.always_show (dbEvt:: CMM.Event)
            , orgId = fromId $ CMM.org_id (dbEvt:: CMM.Event)
            , leagueId = fromId <$> CMM.league_id (dbEvt:: CMM.Event)
            , myRsvp= CMM.response <$> rsvp
            }

eventToDb :: EventInfo -> CMM.Event
eventToDb ei =
  CMM.Event {
    id = def,
    date = def,
    name = name ei,
    org_id = toId $ orgId ei,
    event_type = eventType ei,
    comment = Types.comment (ei::EventInfo),
    always_show = alwaysShow ei,
    league_id = toId <$> leagueId ei
  }

events :: SAS.AuthResult UserData -> Maybe Int -> AppM [EventInfo]
events (SAS.Authenticated user) mevent = do
  conn <- asks dbConn
  events <- liftIO $ runSeldaT (Query.getRelevantEvents $ username (user::UserData)) conn
  return $ map eventFromDb events
events _ _ = forbidden " Pelase Login to see Event info"

insertEvent :: SAS.AuthResult UserData -> EventInfo -> AppM ()
insertEvent (SAS.Authenticated user) event = do
  conn <- asks dbConn
  eid <- liftIO $ runSeldaT (Query.insertEvent $ eventToDb event) conn
  return ()

insertEvent _ _  = forbidden " Pelase Login to add Events"

updateEvent :: SAS.AuthResult UserData -> EventInfo -> AppM ()
updateEvent (SAS.Authenticated user) event = do
  conn <- asks dbConn
  eid <- liftIO $ runSeldaT (Query.updateEvent $ eventToDb event) conn
  return ()

updateEvent _ _ = forbidden " Pelase Login to update"

eventRsvps :: SAS.AuthResult UserData -> Int -> AppM [EventRsvpInfo]
eventRsvps (SAS.Authenticated user) eid = do
  conn <- asks dbConn
  dbRows <- liftIO $ runSeldaT (Query.getEventRsvps $ toId eid) conn
  return $ map eventRsvpInfoFromDb dbRows

eventRsvp :: SAS.AuthResult UserData -> EventRsvpInfo -> AppM ()
eventRsvp (SAS.Authenticated user) er = do
  conn <- asks dbConn
  liftIO $ runSeldaT (Query.recordEventRsvp $ eventRsvpInfoToDb er) conn

updateProfile :: SAS.AuthResult UserData -> Text -> ContactInfo -> AppM ()
updateProfile (SAS.Authenticated _user) uname ci = do
  conn <- asks dbConn
  liftIO $ print "!!!!!!!!!!!! updateProfile  !!!!!!!!!!!!!!!!"
  liftIO $ print ci
  liftIO $ runSeldaT (Query.updateProfile ci) conn
  return ()

updateProfile _ _ _ = forbidden " Pelase Login to update Profile"
-- usersPlayers :: AppM [UserPlayer]
--usersPlayers = dbQuery Query.allUsersPlayers

-- | Create user in database if not already present
-- | This is useful for registering users authenticated thru OIDC
ensureDBUser :: UserData -> AppM UserData
ensureDBUser uD = do
  mu <- dbQuery $ Query.getUserByEmail (Types.email (uD :: UserData))
  case mu of
    [dbUser] -> do
      let un = CMM.username (dbUser :: CMM.User)
      let (userData :: UserData) = Types.modUserName un uD
      pure userData
    _ -> do
      -- if email, strip domain part
      let un = Text.takeWhile (/= '@') $ getUserName uD
      let em = email (uD :: UserData)
      eU <- createUser un Nothing em
      case eU of
        Left err -> forbidden err
        Right _  -> pure $ Types.modUserName un uD

checkPasswd :: Text -> Text -> AppM (Maybe CMM.User)
checkPasswd username pswd = do
  mu <- getUser username
  pure $ case mu of
    Nothing -> Nothing
    Just u -> if validatePassword pswd (CMM.password (u :: CMM.User)) then Just u else Nothing

createResetSecret :: Text -> AppM (Maybe Text)
createResetSecret email = do
  conn <- asks dbConn
  liftIO $ runSeldaT (Query.createResetSecret email) conn


getUserFromResetToken :: Text -> AppM (Maybe CMM.User)
getUserFromResetToken resetToken = do
  conn <- asks dbConn
  liftIO $ runSeldaT Query.cleanupResetTokens conn
  mu <- dbQuery $ Query.getUserFromResetToken resetToken
  case mu of
    []  -> return Nothing
    [u] -> return $ Just u

createUser :: Text -> Maybe Text -> Text -> AppM (Either Text CMM.User)
createUser username pswd email = do
  mu <- getUser username
  case mu of
    Nothing -> do
      ts <- liftIO getCurrentTime
      conn <- asks dbConn
      hashed <- liftIO $ case pswd of
        Just p -> makeDjangoPassword p
        _      -> pure "-- No Password. User created from OIDC login --"

      let u = CMM.User { id = def
                        , username = username
                        , password = hashed
                        , last_login = Nothing
                        , first_name = ""
                        , last_name = ""
                        , email = Just email
                        , is_staff = True
                        , is_active = True
                        , is_superuser = False
                        , email_verified = False
                        , date_joined = ts
                        }
      liftIO $ Query.insertUserPlayer conn u
      pure $ Right u
    Just _ -> pure $ Left $ "User " <> username <> " exists"

dbQuery :: SqlRow b => Query PG (Row PG b) -> AppM [b]
dbQuery q = do
  conn <- asks dbConn
  liftIO $ runSeldaT (query q) conn
