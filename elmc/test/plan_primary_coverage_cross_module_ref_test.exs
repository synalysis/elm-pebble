defmodule Elmc.PlanPrimaryCoverageCrossModuleRefTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.PrimaryCoverage

  test "main_functions_report resolves cross-module nullary qualified_ref via full decl_map" do
    # Main.useDefault references Other.defaults as a CAF/qualified_ref. Coverage must
    # still lower against the full program decl_map (not a Main-only subset).
    other_defaults = %{
      name: "defaults",
      args: [],
      type: nil,
      expr: %{
        op: :record_literal,
        fields: [%{name: "n", expr: %{op: :int_literal, value: 1}}]
      }
    }

    main_use = %{
      name: "useDefault",
      args: [],
      type: nil,
      expr: %{
        op: :record_update,
        base: %{op: :qualified_ref, target: "Other.defaults"},
        fields: [%{name: "n", expr: %{op: :int_literal, value: 2}}]
      }
    }

    decl_map = %{
      {"Other", "defaults"} => other_defaults,
      {"Main", "useDefault"} => main_use
    }

    report = PrimaryCoverage.main_functions_report(decl_map)

    assert report.total == 1
    assert report.failed == []
    assert report.lowered == 1
  end
end
