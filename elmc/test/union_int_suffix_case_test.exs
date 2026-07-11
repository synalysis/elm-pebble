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

  test "extract_fusion_data recognizes direct and maybe-map union suffix shapes" do
    direct_expr = %{
      op: :case,
      subject: %{op: :var, name: "speed"},
      branches: [
        %{
          pattern: %{kind: :constructor, name: "MetersPerSecond", tag: 1, bind: "value", arg_pattern: nil},
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
          pattern: %{kind: :constructor, name: "MilesPerHour", tag: 2, bind: "value", arg_pattern: nil},
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

    maybe_expr = %{
      name: "caseSubject",
      op: :let_in,
      value_expr: %{
        op: :qualified_call,
        target: "Maybe.map",
        args: [
          %{
            op: :lambda,
            body: %{op: :field_access, arg: "fieldAccessorArg", field: "temperature"}
          },
          %{op: :field_access, arg: %{op: :var, name: "model"}, field: "weather"}
        ]
      },
      in_expr: %{
        op: :case,
        subject: "caseSubject",
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing", tag: 0},
            expr: %{op: :string_literal, value: "--"}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "Just",
              tag: 1,
              arg_pattern: %{kind: :constructor, name: "Celsius", tag: 1, bind: "c10", arg_pattern: nil}
            },
            expr: %{
              op: :call,
              name: "__append__",
              args: [
                %{
                  op: :qualified_call,
                  target: "String.fromInt",
                  args: [
                    %{
                      op: :call,
                      name: "__idiv__",
                      args: [
                        %{op: :add_const, var: "c10", value: 5},
                        %{op: :int_literal, value: 10}
                      ]
                    }
                  ]
                },
                %{op: :string_literal, value: "C"}
              ]
            }
          }
        ]
      }
    }

    Process.put(:elmc_record_alias_shapes, %{
      {"Main", "Model"} => ["weather"],
      {"Main", "Weather"} => ["temperature"]
    })

    Process.put(:elmc_record_field_types, %{
      {"Main", "Model"} => %{"weather" => "Maybe Weather"},
      {"Main", "Weather"} => %{"temperature" => "Temperature"}
    })

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_record_field_types)
    end)

    assert {:ok, :union_int_suffix,
            %{
              mode: :direct,
              branches: [
                %{tag: 1, prefix: "", suffix: "m/s", expr: %{kind: :var}},
                %{tag: 2, prefix: "", suffix: "mph", expr: %{kind: :var}}
              ]
            }} =
             UnionIntSuffixCase.extract_fusion_data("Main", "windSpeedString", direct_expr, %{
               {"Main", "windSpeedString"} => %{args: ["speed"]}
             })

    assert {:ok, :union_int_suffix,
            %{
              mode: :maybe_map_field,
              nothing: "--",
              outer_field: 0,
              inner_field: 0,
              branches: [%{tag: 1, suffix: "C", expr: %{kind: :scaled, offset: 5, divisor: 10}}]
            }} =
             UnionIntSuffixCase.extract_fusion_data("Main", "temperatureString", maybe_expr, %{
               {"Main", "temperatureString"} => %{args: ["model"], type: "Model -> String"}
             })
  end
end
