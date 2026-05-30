defmodule ElmExecutor.JnrViewFixTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.CoreIREvaluator

  test "bitmap_resource_id_from_value resolves ctor via bitmap_resource_indices" do
    context = %{bitmap_resource_indices: %{"BitmapStaticJumpHero" => 2}}

    assert {:ok, 2} =
             CoreIREvaluator.bitmap_resource_id_from_value(
               %{"ctor" => "BitmapStaticJumpHero", "args" => []},
               context
             )

    assert {:ok, 0} =
             CoreIREvaluator.bitmap_resource_id_from_value(
               %{"ctor" => "NoBitmap", "args" => []},
               context
             )
  end
end
