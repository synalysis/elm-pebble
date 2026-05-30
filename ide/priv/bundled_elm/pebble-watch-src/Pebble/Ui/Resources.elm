module Pebble.Ui.Resources exposing
    ( AnimatedBitmap(..)
    , AnimatedBitmapInfo
    , AnimatedVector(..)
    , AnimatedVectorInfo
    , Font(..)
    , FontInfo
    , StaticBitmap(..)
    , StaticBitmapInfo
    , StaticVector(..)
    , StaticVectorInfo
    , allAnimatedBitmaps
    , allAnimatedVectors
    , allFonts
    , allStaticBitmaps
    , allStaticVectors
    , animatedBitmapInfo
    , animatedVectorInfo
    , fontInfo
    , staticBitmapInfo
    , staticVectorInfo
    )


type StaticBitmap
    = NoStaticBitmap


type alias StaticBitmapInfo =
    { staticBitmap : StaticBitmap
    , name : String
    , width : Int
    , height : Int
    }


allStaticBitmaps : List StaticBitmap
allStaticBitmaps =
    [ NoStaticBitmap ]


staticBitmapInfo : StaticBitmap -> StaticBitmapInfo
staticBitmapInfo staticBitmap =
    case staticBitmap of
        NoStaticBitmap ->
            { staticBitmap = NoStaticBitmap, name = "NoStaticBitmap", width = 0, height = 0 }


type AnimatedBitmap
    = NoAnimatedBitmap


type alias AnimatedBitmapInfo =
    { animatedBitmap : AnimatedBitmap
    , name : String
    , width : Int
    , height : Int
    , frameCount : Int
    , durationMs : Int
    }


allAnimatedBitmaps : List AnimatedBitmap
allAnimatedBitmaps =
    [ NoAnimatedBitmap ]


animatedBitmapInfo : AnimatedBitmap -> AnimatedBitmapInfo
animatedBitmapInfo animatedBitmap =
    case animatedBitmap of
        NoAnimatedBitmap ->
            { animatedBitmap = NoAnimatedBitmap, name = "NoAnimatedBitmap", width = 0, height = 0, frameCount = 0, durationMs = 0 }


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
    case font of
        DefaultFont ->
            { font = DefaultFont, name = "DefaultFont", height = 0 }


type StaticVector
    = NoStaticVector


type alias StaticVectorInfo =
    { staticVector : StaticVector
    , name : String
    }


allStaticVectors : List StaticVector
allStaticVectors =
    [ NoStaticVector ]


staticVectorInfo : StaticVector -> StaticVectorInfo
staticVectorInfo staticVector =
    case staticVector of
        NoStaticVector ->
            { staticVector = NoStaticVector, name = "NoStaticVector" }


type AnimatedVector
    = NoAnimatedVector


type alias AnimatedVectorInfo =
    { animatedVector : AnimatedVector
    , name : String
    }


allAnimatedVectors : List AnimatedVector
allAnimatedVectors =
    [ NoAnimatedVector ]


animatedVectorInfo : AnimatedVector -> AnimatedVectorInfo
animatedVectorInfo animatedVector =
    case animatedVector of
        NoAnimatedVector ->
            { animatedVector = NoAnimatedVector, name = "NoAnimatedVector" }
