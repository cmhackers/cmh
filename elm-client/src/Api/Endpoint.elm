module Api.Endpoint exposing (Endpoint, follow, login, googleLogin, register,
                              resetPassword, profiles, request, profile, users,
                              players, events, task, eventRsvp, eventRsvps,
                              matches, match)

import Http
import Platform exposing (Task)
import Url.Builder exposing(..)
import Username exposing (Username)
import Email exposing (Email, toString)


{-| Http.request, except it takes an Endpoint instead of a Url.
-}
request :
    { body : Http.Body
    , expect : Http.Expect a
    , headers : List Http.Header
    , method : String
    , timeout : Maybe Float
    , url : Endpoint
    , tracker : Maybe String
    }
    -> Cmd a
request config =
    Http.request
        { body = config.body
        , expect = config.expect
        , headers = config.headers
        , method = config.method
        , timeout = config.timeout
        , url = unwrap config.url
        , tracker = config.tracker
        }

-- | task Added by Murali
task :
    { body : Http.Body
    -- , expect : Http.Expect a
    , headers : List Http.Header
    , method : String
    , timeout : Maybe Float
    , url : Endpoint
    --, tracker : Maybe String
    }
    -> Task Http.Error  (Http.Response String)
task config =
    Http.task
        { method = config.method
        , headers = config.headers
        , url = unwrap config.url
        , body = config.body
        , resolver = Http.stringResolver Ok
        , timeout = config.timeout
        --, expect = config.expect
        -- , tracker = config.tracker
        }



-- TYPES


{-| Get a URL to the Conduit API.

This is not publicly exposed, because we want to make sure the only way to get one of these URLs is from this module.

-}
type Endpoint
    = Endpoint String


unwrap : Endpoint -> String
unwrap (Endpoint str) =
    str


serverUrl = ""
url : List String -> List QueryParameter -> Endpoint
url paths queryParams =
    -- NOTE: Url.Builder takes care of percent-encoding special URL characters.
    -- See https://package.elm-lang.org/packages/elm/url/latest/Url#percentEncode
    Url.Builder.crossOrigin serverUrl
        ("api":: paths)
        queryParams
        |> Endpoint



-- ENDPOINTS


login : Endpoint
login =
    Url.Builder.crossOrigin serverUrl ["login"] [] |> Endpoint -- url [ "login" ] []

googleLogin : Endpoint
googleLogin = Url.Builder.crossOrigin serverUrl ["google"] [] |> Endpoint

register : Endpoint
register =
    Url.Builder.crossOrigin serverUrl ["register"] [] |> Endpoint -- url [ "register" ] []

resetPassword : String -> Endpoint
resetPassword email =
    Url.Builder.crossOrigin serverUrl ["reset_password"] [string "email"  email] |> Endpoint

profile : Username -> Endpoint
profile username =
    url [ "profile", Username.toString username ] []

players : Endpoint
players = url ["players"] []

events : Endpoint
events = url ["events"] []

matches : Endpoint
matches = url ["matches"] []

match : Maybe Int -> Endpoint
match mmatchId = url ["match"] <| case mmatchId of
                                    Nothing -> []
                                    Just matchId -> [int "matchId" matchId]

eventRsvp : Endpoint
eventRsvp = url ["event_rsvp"] []

eventRsvps : Int -> Endpoint
eventRsvps eventId = url ["event_rsvps", String.fromInt eventId] []


users : Endpoint
users =
    url [ "users" ] []


follow : Username -> Endpoint
follow uname =
    url [ "profiles", Username.toString uname, "follow" ] []




profiles : Username -> Endpoint
profiles uname =
    url [ "profiles", Username.toString uname ] []


