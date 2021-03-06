module Tennis.Info exposing (Model, viewInfo)
import Api exposing (Cred)
--import Css exposing (..)
import Bootstrap.Button as Button
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Text as Text
import Element exposing (link)
import Html exposing (..)
import Html.Attributes exposing (class, href, placeholder, value)
--import Html.Styled exposing (..)
--import Html.Styled.Attributes exposing (..)
--import Html.Styled.Events exposing (..)
import Html.Events exposing (onInput)
import Html.Styled.Attributes exposing (css)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Page
import Route exposing (Route)
import Session exposing (Session)
import Time
import Username exposing(..)
import Bootstrap.Table as Table
import Log
import Fuzzy

import Bootstrap.Table as Table

-- MODEL

type Model = Model Internals

type alias Internals =
    { dummy : Int
    }


init : Session -> Model
init session =
    Model
        { dummy = 0
        }

-- VIEW

viewInfo : Time.Zone -> List (Html a)
viewInfo _ =
    [ div []
          [ Card.config [ Card.align Text.alignXsCenter ]
              |> Card.block [] teamsBlockContents
              |> Card.view
          , Card.config [ Card.align Text.alignXsCenter ]
              |> Card.block [] contactBlockContents
              |> Card.view
          --
          --, Card.config [ Card.align Text.alignXsCenter, Card.attrs [class "mt-4"] ]
          --    |> Card.headerH3 [] [ text "C H" ]
          --    |> Card.block [] []
          --    |> Card.footer [] [ text "C F" ]
          --    |> Card.view
          ]
    ]

teamsBlockContents : List (Block.Item msg)
teamsBlockContents =
    [ Block.text [] [ a [href "https://py.cmhackers.com"] [text "Old Site"] ]
    , Block.text [] [ text "We are a Tennis club based in Central New Jersey." ]
    , Block.titleH3 [] [ text "USTA Tennis Teams" ]
    , Block.custom <|
        Table.table
        { options = [ Table.striped, Table.hover, Table.small ]
        , thead =  Table.simpleThead
            [ Table.th [] [ text "Team" ]
            , Table.th [] [ text "Captain" ]
            ]
        , tbody =
            Table.tbody []
                [ Table.tr []
                    [ Table.td [] [a [href "https://tennislink.usta.com/Leagues/Main/StatsAndStandings.aspx?t=R-17&search=kart%20badr&OrgURL=https://tennislink.usta.com/Leagues/Common/Home.aspx#&&s=3%7c%7c0%7c%7c3512706661%7c%7c2022"]
                                     [text "USTA 4.0 18+"]]
                    , Table.td [] [text "Karthik Badri/Ankush Kumar"]
                    ]
                , Table.tr []
                    [ Table.td [] [a [href "https://tennislink.usta.com/Leagues/Main/StatsAndStandings.aspx?t=R-17&search=hari%20nank#&&s=3%7c%7c0%7c%7c3512709572%7c%7c2022"]
                                     [text "USTA 4.0 40+ Spartans"]]
                    , Table.td [] [text "Harish Nankani/Gopal Thirukallam"]
                    ]
                , Table.tr []
                    [ Table.td [] [a [href "https://tennislink.usta.com/Leagues/Main/StatsAndStandings.aspx?t=R-17&search=mura%20dont&OrgURL=https://tennislink.usta.com/Leagues/Common/Home.aspx#&&s=3%7c%7c0%7c%7c3512713672%7c%7c2022"]
                                     [text "USTA 4.0 40+ Cheetahs"]]
                    , Table.td [] [text "Bryan Botsch/Ram Donthireddy"]
                    ]
                , Table.tr []
                    [ Table.td [] [a [href "https://tennislink.usta.com/Leagues/Main/StatsAndStandings.aspx?t=R-17&search=vaib%20shin#&&s=3%7c%7c0%7c%7c3512709906%7c%7c2022"]
                                     [text "USTA 3.5 18+"]]
                    , Table.td [] [text "Vaibhav Shinde/Ravi Bhatheja"]
                    ]
                , Table.tr []
                    [ Table.td [] [a [href "https://tennislink.usta.com/Leagues/Main/StatsAndStandings.aspx?t=R-17&search=vaib%20shin#&&s=3%7c%7c0%7c%7c3512709839%7c%7c2022"]
                                     [text "USTA 3.5 40+"]]
                    , Table.td [] [text "Vaibhav Shinde/Ravi Bhatheja"]
                    ]
                ]
        }
    ]

contactBlockContents : List (Block.Item msg)
contactBlockContents =
    [ Block.titleH3 [] [ text "Contact" ]
    , Block.link [href "mailto:bbotsch3@gmail.com,sak0007@yahoo.com"] [text "Email our captain"]
    ]

sampleBlockContents : List (Block.Item msg)
sampleBlockContents =
    [ Block.titleH3 [] [ text "Contact" ]
    , Block.text [] [ text "" ]
    , Block.custom <|
        Button.button [ Button.primary ] [ text "Go somewhere" ]
    ]
-- UPDATE


type Msg
    = ClickedDismissErrors


update : Maybe Cred -> Msg -> Model -> ( Model, Cmd Msg )
update maybeCred msg (Model model) =
    case msg of
        ClickedDismissErrors ->
            ( Model model, Cmd.none )
