defmodule Elmc.PlanLinearCaseTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function

  @moduletag :plan_surface

  test "three-arm int case uses guarded switch CFG" do
    decl = %{
      name: "pick",
      args: ["n"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "n"},
        branches: [
          %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 10}},
          %{pattern: %{kind: :int, value: 2}, expr: %{op: :int_literal, value: 20}},
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "pick"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "switch_tag" or text =~ "br_if"
  end

  test "qualified constructor case lowers" do
    Process.put(:elmc_constructor_tags, %{"Maybe.Nothing" => 0, "Maybe.Just" => 1})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "fromMaybe",
      args: ["m"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "m"},
        branches: [
          %{
            pattern: %{kind: :qualified_constructor, name: "Maybe.Nothing"},
            expr: %{op: :int_literal, value: 0}
          },
          %{
            pattern: %{kind: :var, name: "x"},
            expr: %{op: :var, name: "x"}
          }
        ]
      }
    }

    decl_map = %{{"Probe", "fromMaybe"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    assert plan != nil
  end

  test "single-branch tuple wildcard case lowers" do
    decl = %{
      name: "bindCmd",
      args: ["pair"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "pair"},
        branches: [
          %{
            pattern: %{
              kind: :tuple,
              elements: [%{kind: :wildcard}, %{kind: :var, name: "cmd"}]
            },
            expr: %{op: :var, name: "cmd"}
          }
        ]
      }
    }

    decl_map = %{{"Probe", "bindCmd"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    assert inspect(plan.blocks) =~ "tuple_proj"
  end

  test "fixed-length cons-nil case with list literal arm verifies" do
    decl = %{
      name: "polygonLines",
      args: ["color", "points"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "points"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "List.::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "a"},
                  %{
                    kind: :constructor,
                    name: "::",
                    resolved_name: "List.::",
                    arg_pattern: %{
                      kind: :tuple,
                      elements: [
                        %{kind: :var, name: "b"},
                        %{
                          kind: :constructor,
                          name: "::",
                          resolved_name: "List.::",
                          arg_pattern: %{
                            kind: :tuple,
                            elements: [
                              %{kind: :var, name: "c"},
                              %{kind: :constructor, name: "[]", resolved_name: "[]", arg_pattern: nil}
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            },
            expr: %{
              op: :list_literal,
              items: [
                %{op: :int_literal, value: 1},
                %{op: :int_literal, value: 2},
                %{op: :int_literal, value: 3}
              ]
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :list_literal, items: []}}
        ]
      }
    }

    decl_map = %{{"Probe", "polygonLines"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "list_head"
    refute text =~ "dest: :fn_out"
  end

  test "constructor case with string payload pattern lowers" do
    Process.put(:elmc_constructor_tags, %{"Companion.Types.PushString" => 7})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "matchString",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "PushString",
              tag: 7,
              resolved_name: "Companion.Types.PushString",
              arg_pattern: %{kind: :string, value: "elm"}
            },
            expr: %{op: :int_literal, value: 1}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "matchString"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "test_string_literal" or text =~ "union_payload"
  end

  test "three-arm tagged constructor case uses tag switch" do
    Process.put(:elmc_constructor_tags, %{"Msg.A" => 1, "Msg.B" => 2, "Msg.C" => 3})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "route",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.A", tag: 1},
            expr: %{op: :int_literal, value: 10}
          },
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.B", tag: 2},
            expr: %{op: :int_literal, value: 20}
          },
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.C", tag: 3},
            expr: %{op: :int_literal, value: 30}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "route"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "switch_tag" or text =~ "switch_ctor_tag"
  end
end
