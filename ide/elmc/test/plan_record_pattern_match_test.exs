defmodule Elmc.PlanRecordPatternMatchTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.TagSwitch
  alias Elmc.Backend.Plan.Lower.{Case, PatternMatch}

  test "match_condition accepts record field-bind patterns" do
    pattern = %{kind: :record, fields: ["data"], bind: nil}
    b = Builder.new("Main", "probe", args: [], rc_required: true)
    {reg, b} = Builder.fresh_reg(b)

    assert {:ok, _cond, _b1} = PatternMatch.match_condition(pattern, reg, b)
  end

  test "constructor payload Texture { data } matches and case binds data" do
    Process.put(:elmc_constructor_tags, %{
      "Types.UnlitMaterial" => 1,
      "UnlitMaterial" => 1,
      "Types.UseMeshUvs" => 2,
      "UseMeshUvs" => 2,
      "Types.Texture" => 3,
      "Texture" => 3,
      "Types.Constant" => 4,
      "Constant" => 4
    })

    branches = [
      %{
        pattern: %{
          kind: :constructor,
          name: "Types.UnlitMaterial",
          tag: 1,
          arg_pattern: %{
            kind: :tuple,
            elements: [
              %{kind: :wildcard},
              %{
                kind: :constructor,
                name: "Types.Constant",
                tag: 4,
                bind: "color",
                arg_pattern: nil
              }
            ]
          }
        },
        expr: %{op: :var, name: "color"}
      },
      %{
        pattern: %{
          kind: :constructor,
          name: "Types.UnlitMaterial",
          tag: 1,
          arg_pattern: %{
            kind: :tuple,
            elements: [
              %{
                kind: :constructor,
                name: "Types.UseMeshUvs",
                tag: 2,
                arg_pattern: nil
              },
              %{
                kind: :constructor,
                name: "Types.Texture",
                tag: 3,
                arg_pattern: %{kind: :record, fields: ["data"], bind: nil}
              }
            ]
          }
        },
        expr: %{op: :var, name: "data"}
      }
    ]

    ctx =
      Context.new(
        module: "Scene3d.Entity",
        function_name: "triangleMesh_probe",
        params: ["material"],
        decl_map: %{},
        rc_required: true
      )

    b0 = Builder.new("Scene3d.Entity", "triangleMesh_probe", args: ["material"], rc_required: true)
    subject = %{op: :var, name: "material"}

    assert {:ok, _reg, _b1} = TagSwitch.compile(subject, branches, ctx, b0)
    assert {:ok, _reg, _b2} = Case.compile(%{op: :case, subject: subject, branches: branches}, ctx, b0)
  end
end
