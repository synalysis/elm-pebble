module RcTrackDebugProbe exposing (probeLog, probeToString, probeTodo)

import Debug


probeLog : Int
probeLog =
    Debug.log "rc" 42


probeTodo : Int
probeTodo =
    Debug.todo "rc"


probeToString : Int
probeToString =
    String.length (Debug.toString 99)
