defmodule Elmc.QualifiedFieldCallTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Call

  test "parse_target fallback splits only on first dot for field calls" do
    decl_map = %{
      {"Route.Articles.WhyElmForPebble", "route"} => %{name: "route", args: []}
    }

    ctx = %{
      module: "Main",
      decl_map: decl_map,
      params: [],
      dest_stack: [:scratch],
      function_tail: false
    }

    assert Call.parse_target("Route.Articles.WhyElmForPebble.route.data", ctx, decl_map) ==
             {"Route", "Articles.WhyElmForPebble.route.data"}
  end

  test "parse_target keeps Elm.Kernel module path when callee is absent from decl_map" do
    ctx = %{
      module: "Basics",
      decl_map: %{},
      params: [],
      dest_stack: [:scratch],
      function_tail: false
    }

    assert Call.parse_target("Elm.Kernel.Utils.gt", ctx, %{}) ==
             {"Elm.Kernel.Utils", "gt"}

    assert Call.parse_target("Elm.Kernel.String.fromNumber", ctx, %{}) ==
             {"Elm.Kernel.String", "fromNumber"}
  end
end

