module Battle exposing
    ( Scene(..)
    , advance
    , initialScene
    , isAnimating
    , resetBattle
    )

{-| Battle animation scenes ported from PokeWatch's scene state machine.
-}


type Scene
    = Waiting
    | WildAppears Int
    | OpponentShown Int
    | AttackAnnounce Int
    | AttackFrame1
    | AttackFrame2
    | AttackFrame3
    | HealthDrain
    | FaintSlide
    | Fainted Int
    | Victory Int
    | Done


initialScene : Scene
initialScene =
    Waiting


isAnimating : Scene -> Bool
isAnimating scene =
    case scene of
        Waiting ->
            False

        Done ->
            False

        _ ->
            True


resetBattle : { scene | scene : Scene, opponentHealth : Float, opponentYOffset : Int, repeatA : Int, repeatB : Int } -> scene
resetBattle model =
    { model
        | scene = Waiting
        , opponentHealth = 1
        , opponentYOffset = 0
        , repeatA = 0
        , repeatB = 0
    }


{-| Advance one animation tick (PokeWatch used ~500 ms timer ticks).
Returns the next scene and whether the battle sequence has finished.
-}
advance :
    Scene
    ->
        { opponentHealth : Float
        , opponentYOffset : Int
        }
    ->
        ( Scene, Bool )
advance scene health =
    case scene of
        Waiting ->
            ( WildAppears 2, False )

        WildAppears repeats ->
            if repeats > 0 then
                ( WildAppears (repeats - 1), False )

            else
                ( OpponentShown 2, False )

        OpponentShown repeats ->
            if repeats > 0 then
                ( OpponentShown (repeats - 1), False )

            else
                ( AttackAnnounce 3, False )

        AttackAnnounce repeats ->
            if repeats > 0 then
                ( AttackAnnounce (repeats - 1), False )

            else
                ( AttackFrame1, False )

        AttackFrame1 ->
            ( AttackFrame2, False )

        AttackFrame2 ->
            ( AttackFrame3, False )

        AttackFrame3 ->
            ( HealthDrain, False )

        HealthDrain ->
            if health.opponentHealth > 0.1 then
                ( HealthDrain, False )

            else
                ( FaintSlide, False )

        FaintSlide ->
            if health.opponentYOffset < 100 then
                ( FaintSlide, False )

            else
                ( Fainted 3, False )

        Fainted repeats ->
            if repeats > 0 then
                ( Fainted (repeats - 1), False )

            else
                ( Victory 3, False )

        Victory repeats ->
            if repeats > 0 then
                ( Victory (repeats - 1), False )

            else
                ( Done, True )

        Done ->
            ( Done, True )
