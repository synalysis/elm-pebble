module RcTrackTaskProcessProbe exposing
    ( probeFail
    , probeKill
    , probeSleep
    , probeSpawn
    , probeSucceed
    )

import Process
import Task


probeSucceed : Int
probeSucceed =
    let
        _ =
            Task.succeed 7
    in
    7


probeFail : Int
probeFail =
    let
        _ =
            Task.fail 5
    in
    5


probeSpawn : Int
probeSpawn =
    let
        _ =
            Process.spawn (Task.succeed 1)
    in
    1


probeSleep : Int
probeSleep =
    let
        _ =
            Process.sleep 5.0
    in
    1


probeKill : Int
probeKill =
    let
        _ =
            Process.spawn (Task.succeed 1)
                |> Task.andThen Process.kill
    in
    1
