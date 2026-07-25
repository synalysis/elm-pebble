defmodule Elmc.PlanTriangularMeshFieldIndexTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{PatternBind, Record}

  test "alphabetically inferred TriangularMesh fields keep Elm layout (not decl-order shape)" do
    # Union payload `{ faceIndices, vertices }` is stored alphabetically. A
    # declaration-order registered shape with the same field set must not win —
    # that swapped .vertices / .faceIndices and emptied Scene3d cylinder/sphere draws.
    Process.put(:elmc_record_alias_shapes, %{
      {"TriangularMesh", "DeclOrder"} => ["vertices", "faceIndices"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    ctx = Context.new(inferred_param_fields: %{"mesh" => ["faceIndices", "vertices"]})

    base = %{op: :var, name: "mesh"}

    assert Record.field_index_for("faceIndices", ctx, base) =~ ~r/^0\b/
    assert Record.field_index_for("vertices", ctx, base) =~ ~r/^1\b/
    assert Record.resolve_field_index_int("faceIndices", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("vertices", ctx, base) == {:ok, 1}
  end

  test "pattern-bound TriangularMesh local uses alphabetical inferred fields" do
    Process.put(:elmc_record_alias_shapes, %{
      {"TriangularMesh", "DeclOrder"} => ["vertices", "faceIndices"]
    })

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"TriangularMesh", "TriangularMesh"} =>
        "{ vertices : Array vertex, faceIndices : List (Int, Int, Int) }"
    })

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    ctx0 = Context.new(module: "TriangularMesh", function_name: "vertices")
    b0 = Builder.new("TriangularMesh", "vertices", args: ["arg0"], rc_required: false)
    {subject, b1} = Builder.fresh_reg(b0)

    pattern = %{
      kind: :constructor,
      name: "TriangularMesh",
      resolved_name: "TriangularMesh.TriangularMesh",
      arg_pattern: %{kind: :var, name: "mesh"},
      bind: nil
    }

    assert {:ok, ctx1, _} = PatternBind.bind(pattern, ctx0, b1, subject)
    assert ctx1.inferred_param_fields["mesh"] == ["faceIndices", "vertices"]

    base = %{op: :var, name: "mesh"}
    assert Record.field_index_for("faceIndices", ctx1, base) =~ ~r/^0\b/
    assert Record.field_index_for("vertices", ctx1, base) =~ ~r/^1\b/
  end
end
