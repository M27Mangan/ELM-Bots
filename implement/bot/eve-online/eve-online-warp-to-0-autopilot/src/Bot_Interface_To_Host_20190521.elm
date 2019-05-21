{- Do not change this file, as it is used to tell the bot running app which framework your bot depends on.
 -}


module Bot_Interface_To_Host_20190521 exposing
    ( BotEvent(..)
    , BotEventAtTime
    , BotRequest(..)
    , RunInVolatileHostComplete
    , RunInVolatileHostError(..)
    , StartTaskStructure
    , Task(..)
    , TaskResultStructure(..)
    , deserializeBotEventAtTime
    , elmEntryPoint
    , wrapBotStepForSerialInterface
    , wrapInitForSerialInterface
    )

import Json.Decode
import Json.Decode.Extra
import Json.Encode


type alias BotEventAtTime =
    { timeInMilliseconds : Int
    , event : BotEvent
    }


type BotEvent
    = SetSessionTimeLimitInMilliseconds Int
    | TaskResult ResultFromTaskWithId


type BotRequest
    = SetStatusMessage String
    | StartTask StartTaskStructure
    | FinishSession


type alias ResultFromTaskWithId =
    { taskId : TaskId
    , taskResult : TaskResultStructure
    }


type TaskResultStructure
    = CreateVolatileHostResponse (Result CreateVolatileHostError CreateVolatileHostComplete)
    | RunInVolatileHostResponse (Result RunInVolatileHostError RunInVolatileHostComplete)
    | CompleteWithoutResult


type alias CreateVolatileHostError =
    ()


type alias CreateVolatileHostComplete =
    { hostId : String }


type RunInVolatileHostError
    = HostNotFound


type alias RunInVolatileHostComplete =
    { exceptionToString : Maybe String
    , returnValueToString : Maybe String
    , durationInMilliseconds : Int
    }


type alias ReleaseVolatileHostStructure =
    { hostId : String }


type BotStepResult
    = DecodeError String
    | DecodeSuccess (List BotRequest)


{-| Tasks can yield some result to return to the bot. That is why we use the identifier.
-}
type alias StartTaskStructure =
    { taskId : TaskId
    , task : Task
    }


type alias RunInVolatileHostStructure =
    { hostId : String
    , script : String
    }


type Task
    = CreateVolatileHost
    | RunInVolatileHost RunInVolatileHostStructure
    | ReleaseVolatileHost ReleaseVolatileHostStructure
    | Delay DelayTaskStructure


type alias TaskId =
    String


type alias DelayTaskStructure =
    { milliseconds : Int }


wrapBotStepForSerialInterface : (BotEventAtTime -> state -> ( state, List BotRequest )) -> String -> state -> ( state, String )
wrapBotStepForSerialInterface botStep serializedBotEventAtTime stateBefore =
    let
        ( state, response ) =
            case serializedBotEventAtTime |> deserializeBotEventAtTime of
                Err error ->
                    ( stateBefore
                    , ("Failed to deserialize event: " ++ (error |> Json.Decode.errorToString))
                        |> DecodeError
                    )

                Ok botEventAtTime ->
                    stateBefore
                        |> botStep botEventAtTime
                        |> Tuple.mapSecond DecodeSuccess
    in
    ( state, response |> encodeResponseOverSerialInterface |> Json.Encode.encode 0 )


wrapInitForSerialInterface : ( state, List BotRequest ) -> ( state, String )
wrapInitForSerialInterface =
    Tuple.mapSecond (Json.Encode.list encodeBotRequest >> Json.Encode.encode 0)


deserializeBotEventAtTime : String -> Result Json.Decode.Error BotEventAtTime
deserializeBotEventAtTime =
    Json.Decode.decodeString decodeBotEventAtTime


decodeBotEventAtTime : Json.Decode.Decoder BotEventAtTime
decodeBotEventAtTime =
    Json.Decode.map2 BotEventAtTime
        (Json.Decode.field "timeInMilliseconds" Json.Decode.int)
        (Json.Decode.field "event" decodeBotEvent)


decodeBotEvent : Json.Decode.Decoder BotEvent
decodeBotEvent =
    Json.Decode.oneOf
        [ Json.Decode.field "setSessionTimeLimitInMilliseconds" Json.Decode.int
            |> Json.Decode.map SetSessionTimeLimitInMilliseconds
        , Json.Decode.field "taskResult" decodeResultFromTaskWithId
            |> Json.Decode.map TaskResult
        ]


decodeResultFromTaskWithId : Json.Decode.Decoder ResultFromTaskWithId
decodeResultFromTaskWithId =
    Json.Decode.map2 ResultFromTaskWithId
        (Json.Decode.field "taskId" Json.Decode.string)
        (Json.Decode.field "taskResult" decodeTaskResult)


decodeTaskResult : Json.Decode.Decoder TaskResultStructure
decodeTaskResult =
    Json.Decode.oneOf
        [ Json.Decode.field "createVolatileHostResponse" (decodeResult (Json.Decode.succeed ()) decodeCreateVolatileHostComplete)
            |> Json.Decode.map CreateVolatileHostResponse
        , Json.Decode.field "runInVolatileHostResponse" (decodeResult decodeRunInVolatileHostError decodeRunInVolatileHostComplete)
            |> Json.Decode.map RunInVolatileHostResponse
        , Json.Decode.field "completeWithoutResult" (Json.Decode.succeed CompleteWithoutResult)
        ]


decodeCreateVolatileHostComplete : Json.Decode.Decoder CreateVolatileHostComplete
decodeCreateVolatileHostComplete =
    Json.Decode.map CreateVolatileHostComplete
        (Json.Decode.field "hostId" Json.Decode.string)


decodeRunInVolatileHostComplete : Json.Decode.Decoder RunInVolatileHostComplete
decodeRunInVolatileHostComplete =
    Json.Decode.map3 RunInVolatileHostComplete
        (Json.Decode.Extra.optionalField "exceptionToString" Json.Decode.string)
        (Json.Decode.Extra.optionalField "returnValueToString" Json.Decode.string)
        (Json.Decode.field "durationInMilliseconds" Json.Decode.int)


decodeRunInVolatileHostError : Json.Decode.Decoder RunInVolatileHostError
decodeRunInVolatileHostError =
    Json.Decode.oneOf
        [ Json.Decode.field "hostNotFound" (Json.Decode.succeed HostNotFound)
        ]


encodeResponseOverSerialInterface : BotStepResult -> Json.Encode.Value
encodeResponseOverSerialInterface stepResult =
    case stepResult of
        DecodeError errorString ->
            Json.Encode.object [ ( "decodeError", errorString |> Json.Encode.string ) ]

        DecodeSuccess botRequests ->
            Json.Encode.object
                [ ( "decodeSuccess"
                  , Json.Encode.object [ ( "botRequests", botRequests |> Json.Encode.list encodeBotRequest ) ]
                  )
                ]


encodeBotRequest : BotRequest -> Json.Encode.Value
encodeBotRequest botRequest =
    case botRequest of
        SetStatusMessage statusMessage ->
            Json.Encode.object [ ( "setStatusMessage", statusMessage |> Json.Encode.string ) ]

        StartTask startTask ->
            Json.Encode.object [ ( "startTask", startTask |> encodeStartTaskAfterTime ) ]

        FinishSession ->
            Json.Encode.object [ ( "finishSession", Json.Encode.object [] ) ]


encodeStartTaskAfterTime : StartTaskStructure -> Json.Encode.Value
encodeStartTaskAfterTime startTaskAfterTime =
    Json.Encode.object
        [ ( "taskId", startTaskAfterTime.taskId |> encodeTaskId )
        , ( "task", startTaskAfterTime.task |> encodeTask )
        ]


encodeTaskId : TaskId -> Json.Encode.Value
encodeTaskId =
    Json.Encode.string


encodeTask : Task -> Json.Encode.Value
encodeTask task =
    case task of
        CreateVolatileHost ->
            Json.Encode.object [ ( "createVolatileHost", Json.Encode.object [] ) ]

        RunInVolatileHost runInVolatileHost ->
            Json.Encode.object
                [ ( "runInVolatileHost"
                  , Json.Encode.object
                        [ ( "hostId", runInVolatileHost.hostId |> Json.Encode.string )
                        , ( "script", runInVolatileHost.script |> Json.Encode.string )
                        ]
                  )
                ]

        ReleaseVolatileHost releaseVolatileHost ->
            Json.Encode.object
                [ ( "releaseVolatileHost"
                  , Json.Encode.object
                        [ ( "hostId", releaseVolatileHost.hostId |> Json.Encode.string )
                        ]
                  )
                ]

        Delay delay ->
            Json.Encode.object
                [ ( "delay"
                  , Json.Encode.object
                        [ ( "milliseconds", delay.milliseconds |> Json.Encode.int )
                        ]
                  )
                ]


decodeResult : Json.Decode.Decoder error -> Json.Decode.Decoder ok -> Json.Decode.Decoder (Result error ok)
decodeResult errorDecoder okDecoder =
    Json.Decode.oneOf
        [ Json.Decode.field "err" errorDecoder |> Json.Decode.map Err
        , Json.Decode.field "ok" okDecoder |> Json.Decode.map Ok
        ]


{-| Support function-level dead code elimination (<https://elm-lang.org/blog/small-assets-without-the-headache>).
Elm code needed to inform the Elm compiler about our entry points.
-}
elmEntryPoint :
    ( botState, String )
    -> (String -> botState -> ( botState, String ))
    -> (botState -> String)
    -> (String -> botState)
    -> Program Int botState String
elmEntryPoint botInit botStepInterface serializeState deserializeState =
    Platform.worker
        { init = \_ -> ( botInit |> Tuple.first, Cmd.none )
        , update =
            \event stateBefore ->
                botStepInterface "" (stateBefore |> serializeState |> deserializeState) |> Tuple.mapSecond (always Cmd.none)
        , subscriptions = \_ -> Sub.none
        }
