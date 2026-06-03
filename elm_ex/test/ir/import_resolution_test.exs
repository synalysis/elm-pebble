defmodule ElmEx.IR.ImportResolutionTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR.ImportResolution

  @lookup %{
    alias_map: %{"Platform" => "Pebble.Platform"},
    import_unqualified_map: %{"watchface" => "Pebble.Platform"},
    local_call_names: MapSet.new(["boardLayout"]),
    current_module: "Main"
  }

  test "resolve/2 expands import aliases to canonical module names" do
    assert ImportResolution.resolve("Platform.displayShapeIsRound", @lookup) ==
             "Pebble.Platform.displayShapeIsRound"
  end

  test "resolve/2 qualifies unqualified imports" do
    assert ImportResolution.resolve("watchface", @lookup) == "Pebble.Platform.watchface"
  end

  test "resolve/2 qualifies local calls in the current module" do
    assert ImportResolution.resolve("boardLayout", @lookup) == "Main.boardLayout"
  end

  test "resolve/2 does not expand alias across qualified module paths" do
    lookup = %{
      alias_map: %{
        "Companion" => "Pebble.Internal.Companion",
        "Internal" => "Companion.Internal"
      }
    }

    assert ImportResolution.resolve("Companion.companionSend", lookup) ==
             "Pebble.Internal.Companion.companionSend"

    assert ImportResolution.resolve("Companion.Internal.watchToPhoneTag", lookup) ==
             "Companion.Internal.watchToPhoneTag"

    assert ImportResolution.resolve("Internal.watchToPhoneTag", lookup) ==
             "Companion.Internal.watchToPhoneTag"
  end

  test "normalize_expr/2 rewrites qualified_call targets" do
    expr = %{
      op: :qualified_call,
      target: "Platform.displayShapeIsRound",
      args: [%{op: :var, name: "shape"}]
    }

    assert %{op: :qualified_call, target: "Pebble.Platform.displayShapeIsRound"} =
             ImportResolution.normalize_expr(expr, @lookup)
  end

  test "normalize_expr/2 promotes resolved unqualified calls to qualified_call" do
    expr = %{op: :call, name: "watchface", args: []}

    assert %{op: :qualified_call, target: "Pebble.Platform.watchface", args: []} =
             ImportResolution.normalize_expr(expr, @lookup)
  end
end
