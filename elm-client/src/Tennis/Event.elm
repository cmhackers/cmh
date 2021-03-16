module Tennis.Event exposing (
    Model, Msg(..), decoder, init, update, viewEvents,
    Event)
import Api exposing (Cred, username)
import Html exposing (..)
import Html.Attributes exposing ( class)
import Html.Events exposing (onClick)
import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Encode
import Page
import Route exposing (Route)
import Session exposing (Session)
import Time
import Username exposing (toString)
import Bootstrap.Table as Table
import Log
import Api.Endpoint as Endpoint
import Util exposing (httpErrorToString)

-- MODEL

type Model = Model Internals

type alias Event =
    { eventId : Int
    , date : Time.Posix
    , name : String
    ,  eventType: String
    ,  comment : String
    ,  alwaysShow : Bool
    ,  orgId : Int
    ,  leagueId : Int
    ,  myRsvp  :  String
    }
type alias Internals =
    { session: Session
    , errors: List String
    , events: List Event
    , isLoading: Bool
    }


init : Session -> List Event -> Model
init session events =
    Model
        { session = session
        , errors = []
        , events = events
        , isLoading = False
        }

-- VIEW

viewEvents : Time.Zone -> Model -> List (Html Msg)
viewEvents timeZone (Model { events, session, errors }) =
    let
        eventsHtml =
            Table.table
                { options = [ Table.striped, Table.hover, Table.small ]
                , thead =  Table.simpleThead
                    [ Table.th [] [ text "Event" ]
                    , Table.th [] [ text "Date" ]
                    , Table.th [] [ text "Curr Rsvp" ]
                    , Table.th [] [ text "Rsvp" ]
                    ]
                , tbody =
                    Table.tbody [] <| List.map (viewPreview) <| events
                }
    in
    Page.viewErrors ClickedDismissErrors errors :: [eventsHtml]


viewPreview : Event -> Table.Row Msg
viewPreview event =
    Table.tr [  ]
        [ Table.td []
            [ a [ Route.href (Route.EventRsvps event.eventId) ]
                [ text event.name ]
            ]
        ,  Table.td [] [text <| String.map (\c -> if c == 'T' then ' ' else c) <| String.slice 0 16 <| Iso8601.fromTime event.date ]
        ,  Table.td [] [rsvpHtml event.myRsvp ]
        , Table.td []
          [ button [onClick <| Signup event.eventId "A"] [rsvpHtml "A"]
          , text " "
          , button [onClick <| Signup event.eventId "N"] [rsvpHtml "N"]
          ]
        ]

rsvpHtml : String -> Html Msg
rsvpHtml code =
    case code of
        -- https://iconify.design/
        "A" -> i [ class "ion-checkmark-circled"] []
        "N" -> i [ class "ion-minus-circled" ] []
        _ -> text code

-- UPDATE


type Msg
    = ClickedDismissErrors
    | Signup Int String
    | SignupCompleted (Result Http.Error Int)


update : Maybe Cred -> Msg -> Model -> ( Model, Cmd Msg )
update maybeCred msg (Model model) =
    case msg of
        ClickedDismissErrors ->
            ( Model { model | errors = [] }, Cmd.none )
        Signup eventId response ->
          case maybeCred of
            Nothing -> (Model model, Log.dbg <| " Unauthorized Signup " ++ String.fromInt eventId ++ " " ++ response)
            Just cred ->
              (Model model, Cmd.batch
              [ Log.dbg <| "Signup " ++ String.fromInt eventId ++ " " ++ response
              , Api.post (Endpoint.eventRsvp) maybeCred (Http.jsonBody <| Encode.object [ ("eventId", Encode.int eventId)
                              , ("response", Encode.string response)
                              , ("comment", Encode.string "")
                              , ("username", Encode.string  <| toString <| username cred)
                              ]) (Decode.succeed 0) SignupCompleted
              ])
        SignupCompleted result ->
            case result of
                Ok _ -> (Model model, Log.dbg "Signup OK")
                Err err -> (Model model, Log.dbg <| httpErrorToString err)


-- SERIALIZATION


eventDecoder : Decoder Event
eventDecoder =
    Decode.succeed Event
        |> required "eventId" Decode.int
        |> required "date" Iso8601.decoder
        |> required "name" Decode.string
        |> required "eventType" Decode.string
        |> required "comment" Decode.string
        |> required "alwaysShow" Decode.bool
        |> required "orgId" Decode.int
        |> optional "leagueId" Decode.int 0
        |> optional "myRsvp" Decode.string ""

decoder : Maybe Cred -> Int -> Decoder (List Event)
decoder maybeCred resultsPerPage =
    Decode.list eventDecoder


