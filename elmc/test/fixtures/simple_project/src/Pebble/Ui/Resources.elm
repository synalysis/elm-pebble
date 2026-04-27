module Pebble.Ui.Resources exposing (Bitmap(..), Font(..), allBitmaps, allFonts)

type Bitmap
    = NoBitmap


allBitmaps : List Bitmap
allBitmaps =
    [ NoBitmap ]


type Font
    = DefaultFont


allFonts : List Font
allFonts =
    [ DefaultFont ]
