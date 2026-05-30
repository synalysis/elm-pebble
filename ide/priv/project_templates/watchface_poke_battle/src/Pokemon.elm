module Pokemon exposing
    ( Attack(..)
    , Opponent
    , Player
    , PlayerSpecies(..)
    , Species(..)
    , attackName
    , opponentForTier
    , playerFromSpecies
    , playerSpeciesFromIndex
    , playerSpeciesName
    , speciesName
    , stepTierIndex
    )

import Pebble.Ui.Resources as Resources


type Attack
    = Thunder
    | Psywave
    | Ember
    | Bubble


type Species
    = Charmander
    | Squirtle
    | Bulbasaur
    | Ivysaur
    | Wartortle
    | Charizard
    | Blastoise
    | Missingno


type PlayerSpecies
    = Pikachu
    | PlayerSquirtle
    | Flareon
    | Mew
    | Mewtwo


type alias Opponent =
    { species : Species
    , levelTag : String
    , x : Int
    , y : Int
    , bitmap : Resources.Bitmap
    }


type alias Player =
    { species : PlayerSpecies
    , displayName : String
    , levelTag : String
    , attack : Attack
    , x : Int
    , y : Int
    , bitmap : Resources.Bitmap
    }


speciesName : Species -> String
speciesName species =
    case species of
        Charmander ->
            "Charmander"

        Squirtle ->
            "Squirtle"

        Bulbasaur ->
            "Bulbasaur"

        Ivysaur ->
            "Ivysaur"

        Wartortle ->
            "Wartortle"

        Charizard ->
            "Charizard"

        Blastoise ->
            "Blastoise"

        Missingno ->
            "Missingno"


playerSpeciesName : PlayerSpecies -> String
playerSpeciesName species =
    case species of
        Pikachu ->
            "Pikachu"

        PlayerSquirtle ->
            "Squirtle"

        Flareon ->
            "Flareon"

        Mew ->
            "Mew"

        Mewtwo ->
            "Mewtwo"


attackName : Attack -> String
attackName attack =
    case attack of
        Thunder ->
            "Thunder"

        Psywave ->
            "Psywave"

        Ember ->
            "Ember"

        Bubble ->
            "Bubble"


playerSpeciesFromIndex : Int -> PlayerSpecies
playerSpeciesFromIndex index =
    case modBy 5 index of
        0 ->
            Pikachu

        1 ->
            PlayerSquirtle

        2 ->
            Flareon

        3 ->
            Mew

        _ ->
            Mewtwo


playerFromSpecies : Int -> Int -> PlayerSpecies -> Player
playerFromSpecies screenW screenH species =
    let
        sx x =
            x * screenW // 240

        sy y =
            y * screenH // 240
    in
    case species of
        Pikachu ->
            { species = Pikachu
            , displayName = "Pikachu"
            , levelTag = ":L"
            , attack = Thunder
            , x = sx 40
            , y = sy 148
            , bitmap = Resources.PikachuBack
            }

        PlayerSquirtle ->
            { species = PlayerSquirtle
            , displayName = "Squirtle"
            , levelTag = ":L"
            , attack = Bubble
            , x = sx 47
            , y = sy 159
            , bitmap = Resources.SquirtleBack
            }

        Flareon ->
            { species = Flareon
            , displayName = "Flareon"
            , levelTag = ":L"
            , attack = Ember
            , x = sx 46
            , y = sy 150
            , bitmap = Resources.FlareonBack
            }

        Mew ->
            { species = Mew
            , displayName = "Mew"
            , levelTag = ":L"
            , attack = Psywave
            , x = sx 35
            , y = sy 133
            , bitmap = Resources.MewBack
            }

        Mewtwo ->
            { species = Mewtwo
            , displayName = "Mewtwo"
            , levelTag = ":L"
            , attack = Psywave
            , x = sx 46
            , y = sy 150
            , bitmap = Resources.MewtwoBack
            }


opponent : Int -> Int -> Species -> Opponent
opponent screenW screenH species =
    let
        sx x =
            x * screenW // 240

        sy y =
            y * screenH // 240

        posX160 =
            sx 160

        posY70 =
            sy 70
    in
    case species of
        Charmander ->
            { species = Charmander
            , levelTag = ":L4"
            , x = sx 180
            , y = sy 75
            , bitmap = Resources.Charmander
            }

        Squirtle ->
            { species = Squirtle
            , levelTag = ":L8"
            , x = sx 170
            , y = sy 75
            , bitmap = Resources.Squirtle
            }

        Bulbasaur ->
            { species = Bulbasaur
            , levelTag = ":L15"
            , x = sx 170
            , y = posY70
            , bitmap = Resources.Bulbasaur
            }

        Ivysaur ->
            { species = Ivysaur
            , levelTag = ":L16"
            , x = posX160
            , y = posY70
            , bitmap = Resources.Ivysaur
            }

        Wartortle ->
            { species = Wartortle
            , levelTag = ":L23"
            , x = posX160
            , y = posY70
            , bitmap = Resources.Wartortle
            }

        Charizard ->
            { species = Charizard
            , levelTag = ":L42"
            , x = posX160
            , y = posY70
            , bitmap = Resources.Charizard
            }

        Blastoise ->
            { species = Blastoise
            , levelTag = ":L69"
            , x = posX160
            , y = posY70
            , bitmap = Resources.Blastoise
            }

        Missingno ->
            { species = Missingno
            , levelTag = ":L99"
            , x = posX160
            , y = posY70
            , bitmap = Resources.Missingno
            }


allOpponentTiers : List (List Species)
allOpponentTiers =
    [ [ Charmander, Bulbasaur, Squirtle ]
    , [ Ivysaur, Wartortle ]
    , [ Charizard, Blastoise ]
    , [ Missingno ]
    ]


{-| Maps daily step progress to an opponent tier (0..3), matching PokeWatch tiers.
-}
stepTierIndex : Int -> Int -> Int
stepTierIndex steps stepGoal =
    let
        progress =
            if stepGoal <= 0 then
                0

            else
                (steps * 3) // stepGoal
    in
    if progress >= 6 then
        3

    else if progress >= 2 then
        2

    else
        modBy 3 progress


opponentForTier : Int -> Int -> Int -> Int -> Opponent
opponentForTier screenW screenH tierIndex pick =
    let
        tier =
            allOpponentTiers
                |> List.drop tierIndex
                |> List.head
                |> Maybe.withDefault [ Missingno ]

        species =
            tier
                |> List.drop (modBy (max 1 (List.length tier)) pick)
                |> List.head
                |> Maybe.withDefault Missingno
    in
    opponent screenW screenH species
