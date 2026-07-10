defmodule Elmc.UnionIntSuffixCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.UnionIntSuffixCase

  test "try_emit recognizes union int suffix append case IR" do
    expr = %{
      op: :case,
      subject: %{op: :var, name: "speed"},
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "MetersPerSecond",
            tag: 1,
            bind: "value",
            arg_pattern: nil
          },
          expr: %{
            op: :call,
            name: "__append__",
            args: [
              %{op: :qualified_call, target: "String.fromInt", args: [%{op: :var, name: "value"}]},
              %{op: :string_literal, value: "m/s"}
            ]
          }
        },
        %{
          pattern: %{
            kind: :constructor,
            name: "MilesPerHour",
            tag: 2,
            bind: "value",
            arg_pattern: nil
          },
          expr: %{
            op: :call,
            name: "__append__",
            args: [
              %{op: :qualified_call, target: "String.fromInt", args: [%{op: :var, name: "value"}]},
              %{op: :string_literal, value: "mph"}
            ]
          }
        }
      ]
    }

    assert {:ok, body, [], :rc_native} =
             UnionIntSuffixCase.try_emit("Main", "windSpeedString", expr, %{
               {"Main", "windSpeedString"} => %{args: ["speed"]}
             })

    assert body =~ "switch ("
    assert body =~ "snprintf"
    assert body =~ "%lldm/s"
    refute body =~ "goto elmc_plan_block_"
  end

  test "infer_native_tag_fusion_arg_kinds keeps boxed union param when native helper reads payload" do
    alias Elmc.Backend.CCodegen.Fusion

    helper = """
    static RC elmc_fn_Main_windSpeedString_native(ElmcValue **out, ElmcValue *speed) {
      const int case_msg_tag_1 = 0;
      switch (case_msg_tag_1) {
        case 1: snprintf("x", 1, "%lld", (long long)elmc_as_int(elmc_union_payload(speed))); break;
      }
    }
    """

    assert Fusion.infer_native_tag_fusion_arg_kinds(helper, %{args: ["speed"]}) == [:boxed]
  end

  @tag :slow
  test "try_emit recognizes Maybe.map field access union int suffix case" do
    alias Elmc.Backend.CCodegen.IRQueries
    alias Elmc.TestSupport.TemplateCompile

    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes", plan_ir_mode: :primary)

    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(result.ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(result.ir))

    on_exit(fn ->
      Process.delete(:elmc_record_field_types)
      Process.delete(:elmc_record_alias_shapes)
    end)

    decl_map = TemplateCompile.decl_map_from_result(result)
    decl = Map.fetch!(decl_map, {"Main", "temperatureString"})

    assert {:ok, body, [], :rc_native} =
             UnionIntSuffixCase.try_emit("Main", "temperatureString", decl.expr, decl_map)

    assert body =~ "outer_maybe"
    assert body =~ "snprintf"
    assert body =~ "%lldC"
    assert body =~ "%lldF"
    refute body =~ "goto elmc_plan_block_"
  end
end
