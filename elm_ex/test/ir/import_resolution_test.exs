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

  test "resolve/2 expands Color import alias to canonical module path" do
    lookup = %{
      alias_map: %{"Color" => "Pebble.Ui.Color"},
      import_unqualified_map: %{},
      local_call_names: MapSet.new(),
      current_module: "Yes.Render"
    }

    assert ImportResolution.resolve("Color.oxfordBlue", lookup) ==
             "Pebble.Ui.Color.oxfordBlue"
  end

  test "normalize_expr/2 rewrites qualified_ref import aliases" do
    lookup = %{
      alias_map: %{"Color" => "Pebble.Ui.Color"},
      import_unqualified_map: %{},
      local_call_names: MapSet.new(),
      current_module: "Yes.Render"
    }

    expr = %{op: :qualified_ref, target: "Color.oxfordBlue"}

    assert %{op: :qualified_ref, target: "Pebble.Ui.Color.oxfordBlue"} =
             ImportResolution.normalize_expr(expr, lookup)
  end

  test "normalize_expr/2 rewrites field_access on import alias module vars" do
    lookup = %{
      alias_map: %{"Color" => "Pebble.Ui.Color"},
      import_unqualified_map: %{},
      local_call_names: MapSet.new(),
      current_module: "Yes.Render"
    }

    expr = %{op: :field_access, arg: %{op: :var, name: "Color"}, field: "oxfordBlue"}

    assert %{op: :qualified_call, target: "Pebble.Ui.Color.oxfordBlue", args: []} =
             ImportResolution.normalize_expr(expr, lookup)
  end

  test "normalize_expr/2 rewrites Ui import alias on fillCircle calls" do
    lookup = %{
      alias_map: %{"Ui" => "Pebble.Ui", "Color" => "Pebble.Ui.Color"},
      import_unqualified_map: %{},
      local_call_names: MapSet.new(),
      current_module: "Yes.Render"
    }

    expr = %{
      op: :qualified_call,
      target: "Ui.fillCircle",
      args: [
        %{op: :record_literal, fields: []},
        %{op: :int_literal, value: 50},
        %{op: :qualified_call, target: "Color.oxfordBlue", args: []}
      ]
    }

    assert %{
             op: :qualified_call,
             target: "Pebble.Ui.fillCircle",
             args: [
               _center,
               %{op: :int_literal, value: 50},
               %{op: :qualified_call, target: "Pebble.Ui.Color.oxfordBlue", args: []}
             ]
           } = ImportResolution.normalize_expr(expr, lookup)
  end

  test "resolve/2 picks the aliased module that exports the member" do
    lookup = %{
      alias_map: %{"Svg" => "Internal.Svg.Config"},
      alias_member_map: %{
        "Svg" => %{
          "smallViewport" => "Internal.Svg",
          "default" => "Internal.Svg.Config",
          "layoutToSvgWithConfig" => "Internal.Cartesian.Layout.Svg"
        },
        "Layout" => %{
          "boundOf" => "Internal.Cartesian.Layout",
          "default" => "Diagram.Layout.Config"
        },
        "Arrow" => %{
          "arrow" => "Internal.Svg.Arrow",
          "safeTo" => "Internal.Arrow"
        }
      }
    }

    assert ImportResolution.resolve("Layout.boundOf", lookup) ==
             "Internal.Cartesian.Layout.boundOf"

    assert ImportResolution.resolve("Svg.smallViewport", lookup) ==
             "Internal.Svg.smallViewport"

    assert ImportResolution.resolve("Svg.default", lookup) ==
             "Internal.Svg.Config.default"

    assert ImportResolution.resolve("Arrow.arrow", lookup) ==
             "Internal.Svg.Arrow.arrow"
  end

  test "normalize_expr/2 qualifies imported union constructors" do
    lookup = %{import_unqualified_map: %{"M" => "Svg.PathD", "L" => "Svg.PathD"}}

    assert %{op: :constructor_call, target: "Svg.PathD.M"} =
             ImportResolution.normalize_expr(
               %{op: :constructor_call, target: "M", args: [%{op: :var, name: "p"}]},
               lookup
             )
  end

  test "resolve/2 keeps exposed Svg node helpers when Svg.Attributes uses the Svg alias" do
    lookup = %{
      alias_map: %{"Svg" => "Svg.Attributes"},
      import_unqualified_map: %{"g" => "Svg"}
    }

    assert ImportResolution.resolve("g", lookup) == "Svg.g"
    assert ImportResolution.resolve("Svg.g", lookup) == "Svg.g"
    assert ImportResolution.resolve("Svg.fill", lookup) == "Svg.Attributes.fill"
  end
end
