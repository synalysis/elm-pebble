defmodule Elmc.PlanCylinder3dCenteredOnFieldIndexTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Record
  alias Elmc.Backend.Plan.ParamFieldInference

  test "anonymous {radius,length} args stay alphabetical despite Cylinder3d superset shape" do
    # Cylinder3d.centeredOn reads arguments.radius / arguments.length. Access-order
    # inference yields ["radius","length"], which is a subset of the registered
    # Cylinder3d payload. Using that shape's indices (length=1, radius=2) left the
    # constructed cylinder with radius=0 and preScale (0,0,r) — invisible bodies.
    Process.put(:elmc_record_alias_shapes, %{
      {"Types", "Cylinder3d"} => ["axis", "length", "radius"],
      {"Types", "Cone3d"} => ["axis", "length", "radius"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    expr = %{
      op: :constructor_call,
      target: "Types.Cylinder3d",
      args: [
        %{
          op: :record_literal,
          fields: [
            %{
              name: "axis",
              expr: %{op: :var, name: "axis"}
            },
            %{
              name: "radius",
              expr: %{
                op: :qualified_call,
                target: "Quantity.abs",
                args: [%{op: :field_access, arg: "arguments", field: "radius"}]
              }
            },
            %{
              name: "length",
              expr: %{
                op: :qualified_call,
                target: "Quantity.abs",
                args: [%{op: :field_access, arg: "arguments", field: "length"}]
              }
            }
          ]
        }
      ]
    }

    inferred = ParamFieldInference.infer(%{expr: expr, args: ["arguments"]})
    assert inferred == %{"arguments" => ["radius", "length"]}

    ctx =
      Context.new(
        module: "Cylinder3d",
        function_name: "centeredOn",
        params: ["arguments"],
        inferred_param_fields: inferred
      )

    base = %{op: :var, name: "arguments"}

    assert Record.resolve_field_index_int("length", ctx, base) == {:ok, 0}
    assert Record.resolve_field_index_int("radius", ctx, base) == {:ok, 1}
    assert Record.field_index_for("length", ctx, base) =~ ~r/^0\b/
    assert Record.field_index_for("radius", ctx, base) =~ ~r/^1\b/
  end
end
