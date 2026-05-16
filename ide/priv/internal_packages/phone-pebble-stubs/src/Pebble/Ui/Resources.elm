module Pebble.Ui.Resources exposing
    ( Bitmap(..)
    , BitmapInfo
    , Font(..)
    , FontInfo
    , allBitmaps
    , allFonts
    , bitmapInfo
    , fontInfo
    )


type Bitmap
    = NoBitmap


type alias BitmapInfo =
    { bitmap : Bitmap
    , name : String
    , width : Int
    , height : Int
    }


allBitmaps : List Bitmap
allBitmaps =
    [ NoBitmap ]


bitmapInfo : Bitmap -> BitmapInfo
bitmapInfo bitmap =
    { bitmap = bitmap, name = "NoBitmap", width = 0, height = 0 }


type Font
    = DefaultFont


type alias FontInfo =
    { font : Font
    , name : String
    , height : Int
    }


allFonts : List Font
allFonts =
    [ DefaultFont ]


fontInfo : Font -> FontInfo
fontInfo font =
    { font = font, name = "DefaultFont", height = 0 }
