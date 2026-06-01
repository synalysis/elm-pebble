defmodule Elmx.PebbleUiRuntimeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.Ui

  test "draw_vector_sequence_at accepts two-arg surface form" do
    op = Ui.draw_vector_sequence_at("VectorAnimatedFoo", %{x: 0, y: 0})

    assert op.type == "drawVectorSequenceAt"
    assert op.frame == 0
    assert op.rotation == 0
  end
end
