defmodule Ide.Debugger.HotReloadSurfaceTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.HotReloadSurface

  test "put_view_trees sets watch tree for watch source root" do
    state =
      HotReloadSurface.put_view_trees(
        %{watch: %{}, companion: %{}, phone: %{}},
        "src/Main.elm",
        "rev",
        "watch"
      )

    assert get_in(state, [:watch, :view_tree, "label"]) == "src/Main.elm"
  end

  test "maybe_append_phone_view_render only for phone root" do
    append = fn st, type, _payload -> Map.put(st, :last_event, type) end

    assert %{last_event: "debugger.view_render"} =
             HotReloadSurface.maybe_append_phone_view_render(%{}, "phone", append)

    assert HotReloadSurface.maybe_append_phone_view_render(%{}, "watch", append) == %{}
  end
end
