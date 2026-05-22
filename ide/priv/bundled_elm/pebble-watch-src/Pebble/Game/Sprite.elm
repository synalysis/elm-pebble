module Pebble.Game.Sprite exposing
    ( Sprite
    , parallaxBitmap
    , sprite
    , tileMap
    , view
    )

{-| Lightweight sprite helpers built on top of `Pebble.Ui`.

# Sprites
@docs Sprite, sprite, view

# Helpers
@docs parallaxBitmap, tileMap

-}

import Pebble.Ui as Ui


{-| Bitmap sprite with integer bounds.
-}
type alias Sprite =
    { bitmap : Ui.Bitmap
    , x : Int
    , y : Int
    , w : Int
    , h : Int
    }


{-| Construct a sprite from a bitmap and rectangle.
-}
sprite : Ui.Bitmap -> Ui.Rect -> Sprite
sprite bitmap bounds =
    { bitmap = bitmap
    , x = bounds.x
    , y = bounds.y
    , w = bounds.w
    , h = bounds.h
    }


{-| Render a sprite as a bitmap draw operation.
-}
view : Sprite -> Ui.RenderOp
view item =
    Ui.drawBitmapInRect item.bitmap
        { x = item.x, y = item.y, w = item.w, h = item.h }


{-| Draw a horizontally wrapping bitmap strip for parallax backgrounds.
-}
parallaxBitmap : Ui.Bitmap -> { x : Int, y : Int, w : Int, h : Int } -> Int -> List Ui.RenderOp
parallaxBitmap bitmap bounds offset =
    let
        wrapped =
            modBy bounds.w offset
    in
    [ Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped }
    , Ui.drawBitmapInRect bitmap { bounds | x = bounds.x - wrapped + bounds.w }
    ]


{-| Draw a tile map from tile coordinates, a camera offset, and bitmap resources.
-}
tileMap :
    { tileSize : Int
    , cameraX : Int
    , cameraY : Int
    , tiles : List ( Int, Int, Ui.Bitmap )
    }
    -> List Ui.RenderOp
tileMap config =
    List.map
        (\( x, y, bitmap ) ->
            Ui.drawBitmapInRect bitmap
                { x = x * config.tileSize - config.cameraX
                , y = y * config.tileSize - config.cameraY
                , w = config.tileSize
                , h = config.tileSize
                }
        )
        config.tiles
