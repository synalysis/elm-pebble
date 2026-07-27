defmodule Elmc.MaybeIntStringCaseTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.MaybeIntStringCase

  test "try_emit recognizes maybe field threshold int suffix IR" do
    expr = %{
      name: "caseSubject",
      op: :let_in,
      value_expr: %{arg: "model", op: :field_access, field: "stepsToday"},
      in_expr: %{
        op: :case,
        subject: "caseSubject",
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing", tag: 0, bind: nil, arg_pattern: nil},
            expr: %{op: :string_literal, value: "--"}
          },
          %{
            pattern: %{kind: :constructor, name: "Just", tag: 1, bind: "steps", arg_pattern: nil},
            expr: %{
              op: :if,
              cond: %{
                op: :if,
                cond: %{
                  op: :compare,
                  kind: :gt,
                  left: %{op: :var, name: "steps"},
                  right: %{op: :int_literal, value: 10_000}
                },
                then_expr: %{op: :constructor_call, target: "True", args: []},
                else_expr: %{
                  op: :compare,
                  kind: :eq,
                  left: %{op: :var, name: "steps"},
                  right: %{op: :int_literal, value: 10_000}
                }
              },
              then_expr: %{
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
                        args: [%{op: :var, name: "steps"}, %{op: :int_literal, value: 1000}]
                      }
                    ]
                  },
                  %{op: :string_literal, value: "k"}
                ]
              },
              else_expr: %{
                op: :qualified_call,
                target: "String.fromInt",
                args: [%{op: :var, name: "steps"}]
              }
            }
          }
        ]
      }
    }

    Process.put(:elmc_record_alias_shapes, %{{"Main", "Model"} => ["stepsToday"]})

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    assert {:ok, body, [], :rc_native} =
             MaybeIntStringCase.try_emit("Main", "stepsString", expr, %{
               {"Main", "stepsString"} => %{args: ["model"], type: "Model -> String"}
             })

    assert body =~ "elmc_maybe_is_nothing"
    assert body =~ "steps >= 10000"
    assert body =~ "elmc_int_idiv(steps, 1000)"
    assert body =~ "%lldk"
    refute body =~ "goto elmc_plan_block_"
  end

  test "try_emit recognizes maybe withDefault int suffix append IR" do
    expr = %{
      op: :call,
      name: "__append__",
      args: [
        %{
          op: :qualified_call,
          target: "String.fromInt",
          args: [
            %{
              op: :qualified_call,
              target: "Maybe.withDefault",
              args: [
                %{op: :int_literal, value: 0},
                %{arg: "model", op: :field_access, field: "batteryLevel"}
              ]
            }
          ]
        },
        %{op: :string_literal, value: "%"}
      ]
    }

    Process.put(:elmc_record_alias_shapes, %{{"Main", "Model"} => ["batteryLevel"]})

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    assert {:ok, body, [], :rc_native} =
             MaybeIntStringCase.try_emit("Main", "batteryPercentString", expr, %{
               {"Main", "batteryPercentString"} => %{args: ["model"], type: "Model -> String"}
             })

    assert body =~ "elmc_maybe_with_default_int(0"
    assert body =~ "%lld%%"
    refute body =~ "goto elmc_plan_block_"
  end

  test "extract_fusion_data recognizes default append and maybe case shapes" do
    default_expr = %{
      op: :call,
      name: "__append__",
      args: [
        %{
          op: :qualified_call,
          target: "String.fromInt",
          args: [
            %{
              op: :qualified_call,
              target: "Maybe.withDefault",
              args: [
                %{op: :int_literal, value: 0},
                %{arg: "model", op: :field_access, field: "batteryLevel"}
              ]
            }
          ]
        },
        %{op: :string_literal, value: "%"}
      ]
    }

    case_expr = %{
      name: "caseSubject",
      op: :let_in,
      value_expr: %{arg: "model", op: :field_access, field: "stepsToday"},
      in_expr: %{
        op: :case,
        subject: "caseSubject",
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing", tag: 0, bind: nil, arg_pattern: nil},
            expr: %{op: :string_literal, value: "--"}
          },
          %{
            pattern: %{kind: :constructor, name: "Just", tag: 1, bind: "steps", arg_pattern: nil},
            expr: %{
              op: :if,
              cond: %{
                op: :if,
                cond: %{
                  op: :compare,
                  kind: :gt,
                  left: %{op: :var, name: "steps"},
                  right: %{op: :int_literal, value: 10_000}
                },
                then_expr: %{op: :constructor_call, target: "True", args: []},
                else_expr: %{
                  op: :compare,
                  kind: :eq,
                  left: %{op: :var, name: "steps"},
                  right: %{op: :int_literal, value: 10_000}
                }
              },
              then_expr: %{
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
                        args: [%{op: :var, name: "steps"}, %{op: :int_literal, value: 1000}]
                      }
                    ]
                  },
                  %{op: :string_literal, value: "k"}
                ]
              },
              else_expr: %{
                op: :qualified_call,
                target: "String.fromInt",
                args: [%{op: :var, name: "steps"}]
              }
            }
          }
        ]
      }
    }

    Process.put(:elmc_record_alias_shapes, %{{"Main", "Model"} => ["batteryLevel", "stepsToday"]})

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    decl_map = %{
      {"Main", "batteryPercentString"} => %{args: ["model"], type: "Model -> String"},
      {"Main", "stepsString"} => %{args: ["model"], type: "Model -> String"}
    }

    assert {:ok, :maybe_int_string, %{mode: :default_append, field: 0, default: 0, suffix: "%"}} =
             MaybeIntStringCase.extract_fusion_data("Main", "batteryPercentString", default_expr, decl_map)

    assert {:ok, :maybe_int_string,
            %{
              mode: :maybe_case,
              field: 1,
              nothing: "--",
              format: %{kind: :threshold, threshold: 10_000, divisor: 1000, suffix: "k"}
            }} =
             MaybeIntStringCase.extract_fusion_data("Main", "stepsString", case_expr, decl_map)
  end

  @tag :slow
  test "try_emit fuses watchface_yes batteryPercentString from template IR" do
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
    decl = Map.fetch!(decl_map, {"Main", "batteryPercentString"})

    assert {:ok, body, [], :rc_native} =
             MaybeIntStringCase.try_emit("Main", "batteryPercentString", decl.expr, decl_map)

    assert body =~ "elmc_maybe_with_default_int(0"
    assert body =~ "%lld%%"
  end

  @tag :slow
  test "try_emit fuses watchface_yes stepsString from template IR" do
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
    decl = Map.fetch!(decl_map, {"Main", "stepsString"})

    assert {:ok, body, [], :rc_native} =
             MaybeIntStringCase.try_emit("Main", "stepsString", decl.expr, decl_map)

    assert body =~ "steps >= 10000"
    assert body =~ "%lldk"
  end
end
