defmodule Elmx.PlatformDisplayShapeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Executor.Model
  alias Elmx.Runtime.Pebble.Dispatch.Platform

  test "displayShapeIsRound accepts bare Round atoms from runtime_model_from_elm" do
    model =
      Model.runtime_model_from_elm(%{
        "displayShape" => %{"ctor" => "Round", "args" => []}
      })

    assert model["displayShape"] == :Round
    assert Platform.display_shape_is_round([model["displayShape"]])
  end

  test "displayShapeIsRound accepts wire ctor maps" do
    assert Platform.display_shape_is_round([%{"ctor" => "Round", "args" => []}])
  end
end
