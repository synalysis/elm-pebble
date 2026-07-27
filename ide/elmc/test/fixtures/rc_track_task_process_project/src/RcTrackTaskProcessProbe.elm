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
    case Task.succeed 7 of
        Ok n ->
            n

        Err _ ->
            -1


probeFail : Int
probeFail =
    case Task.fail 5 of
        Ok _ ->
            -1

        Err e ->
            e


probeSpawn : Int
probeSpawn =
    case Process.spawn (Task.succeed 1) of
        Ok _ ->
            1

        Err _ ->
            -1


probeSleep : Int
probeSleep =
    case Process.sleep 5 of
        Ok _ ->
            1

        Err _ ->
            0


probeKill : Int
probeKill =
    case Process.kill 1 of
        Ok _ ->
            1

        Err _ ->
            0
