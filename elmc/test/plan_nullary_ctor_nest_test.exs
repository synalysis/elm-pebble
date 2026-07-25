defmodule Elmc.PlanNullaryCtorNestTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "nullary UseMeshUvs in LambertianMaterial nest is a sibling value, not a unary wrapper" do
    # elm_ex lowers matte to nested tuple2(tag, rest). Nullary UseMeshUvs must
    # compile as tag+unit paired with rest — not (tag, rest) as its payload.
    Process.put(:elmc_constructor_tags, %{
      "Scene3d.Types.LambertianMaterial" => 3,
      "Scene3d.Types.UseMeshUvs" => 1,
      "Scene3d.Types.Constant" => 1,
      "Scene3d.Types.NoNormalMap" => 1
    })

    Process.put(:elmc_union_constructor_payload_specs, %{
      {"Scene3d.Types", "LambertianMaterial"} =>
        "TextureMap (Texture (LinearRgb Unitless)) (Texture Float) NormalMap",
      {"Scene3d.Types", "UseMeshUvs"} => "",
      {"Scene3d.Types", "Constant"} => "value",
      {"Scene3d.Types", "NoNormalMap"} => ""
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_union_constructor_payload_specs)
    end)

    expr = %{
      op: :tuple2,
      left: %{op: :int_literal, value: 3, union_ctor: "Scene3d.Types.LambertianMaterial"},
      right: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1, union_ctor: "Scene3d.Types.UseMeshUvs"},
        right: %{
          op: :tuple2,
          left: %{
            op: :tuple2,
            left: %{op: :int_literal, value: 1, union_ctor: "Scene3d.Types.Constant"},
            right: %{op: :var, name: "linearRgb"}
          },
          right: %{
            op: :tuple2,
            left: %{op: :var, name: "ao"},
            right: %{op: :int_literal, value: 1, union_ctor: "Scene3d.Types.NoNormalMap"}
          }
        }
      }
    }

    decl = %{
      name: "matteShape",
      args: ["linearRgb", "ao"],
      type: "a -> b -> Material",
      expr: expr
    }

    assert {:ok, plan} =
             Function.lower(decl, "Scene3d.Material", %{{"Scene3d.Material", "matteShape"} => decl},
               rc_required: false
             )

    instrs = Enum.flat_map(plan.blocks, & &1.instrs)

    # UseMeshUvs nullary must emit unit (tag+unit), not absorb the Constant nest.
    assert Enum.any?(instrs, fn
             %{op: :call_runtime, args: %{builtin: :unit}} -> true
             _ -> false
           end),
           "expected unit for nullary UseMeshUvs/NoNormalMap"

    # Count tuple2: LM pair + UseMeshUvs pair + Constant pair + AO/NoNormalMap pair = 4
    # plus Constant's (tag, payload) = 5. Unary-wrap bug collapses UseMeshUvs into
    # Constant nest and yields fewer sibling pairings with unit.
    tuple2s =
      Enum.count(instrs, fn
        %{op: :call_runtime, args: %{builtin: :tuple2}} -> true
        _ -> false
      end)

    assert tuple2s >= 5, "expected full nested payload pairs, got #{tuple2s} tuple2s"
  end
end
