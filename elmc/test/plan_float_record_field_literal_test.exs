defmodule Elmc.PlanFloatRecordFieldLiteralTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "Float-typed record field int literals box as new_float" do
    # Scene3d.Transformation.identity uses `scale = 1` (and ix/iy/…) — Elm number
    # polymorphism. Boxing those as TAG_INT poisons later Float ops / MJS peels.
    Process.put(:elmc_record_alias_shapes, %{
      {"Scene3d.Types", "Transformation"} => [
        "isRightHanded",
        "ix",
        "iy",
        "iz",
        "jx",
        "jy",
        "jz",
        "kx",
        "ky",
        "kz",
        "px",
        "py",
        "pz",
        "scale"
      ]
    })

    Process.put(:elmc_record_field_types, %{
      {"Scene3d.Types", "Transformation"} => %{
        "ix" => "Float",
        "iy" => "Float",
        "iz" => "Float",
        "jx" => "Float",
        "jy" => "Float",
        "jz" => "Float",
        "kx" => "Float",
        "ky" => "Float",
        "kz" => "Float",
        "px" => "Float",
        "py" => "Float",
        "pz" => "Float",
        "scale" => "Float",
        "isRightHanded" => "Bool"
      }
    })

    decl = %{
      name: "identity",
      args: [],
      type: "Scene3d.Types.Transformation",
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "ix", expr: %{op: :int_literal, value: 1}},
          %{name: "iy", expr: %{op: :int_literal, value: 0}},
          %{name: "iz", expr: %{op: :int_literal, value: 0}},
          %{name: "jx", expr: %{op: :int_literal, value: 0}},
          %{name: "jy", expr: %{op: :int_literal, value: 1}},
          %{name: "jz", expr: %{op: :int_literal, value: 0}},
          %{name: "kx", expr: %{op: :int_literal, value: 0}},
          %{name: "ky", expr: %{op: :int_literal, value: 0}},
          %{name: "kz", expr: %{op: :int_literal, value: 1}},
          %{name: "px", expr: %{op: :int_literal, value: 0}},
          %{name: "py", expr: %{op: :int_literal, value: 0}},
          %{name: "pz", expr: %{op: :int_literal, value: 0}},
          %{name: "scale", expr: %{op: :int_literal, value: 1}},
          %{name: "isRightHanded", expr: %{op: :bool_literal, value: true}}
        ]
      }
    }

    assert {:ok, plan} =
             Function.lower(
               decl,
               "Scene3d.Transformation",
               %{{"Scene3d.Transformation", "identity"} => decl},
               rc_required: true
             )

    float_news =
      for block <- plan.blocks,
          %{op: :call_runtime, args: %{builtin: :new_float, literal: lit}} <- block.instrs,
          do: lit

    assert 1.0 in float_news
    assert 0.0 in float_news

    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, fn
               %{op: :call_runtime, args: %{builtin: :record_new_values_ints}} -> true
               _ -> false
             end)
           end)
  end
end
