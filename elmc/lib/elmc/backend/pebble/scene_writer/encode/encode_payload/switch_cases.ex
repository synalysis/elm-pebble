defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.{
    Circle,
    CoordsColor,
    DefaultCase,
    FixedScalars,
    Pixel,
    RoundRect,
    TextLabelPrefix
  }

  @spec body() :: Types.c_source()
  def body do
    [
      TextLabelPrefix.body(),
      FixedScalars.body(),
      Pixel.body(),
      CoordsColor.body(),
      Circle.body(),
      RoundRect.body(),
      DefaultCase.body()
    ]
    |> IO.iodata_to_binary()
  end
end
