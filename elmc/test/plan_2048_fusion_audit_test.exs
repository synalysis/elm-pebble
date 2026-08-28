defmodule Elmc.Plan2048FusionAuditTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Fusion.ListIndexedReplace
  alias Elmc.Backend.Plan.Fusion.ListIntSearch
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "ListIndexedReplace recognizes Elm.Kernel.List.indexedMap replace shape" do
    decl = %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      expr: %{
        op: :qualified_call,
        target: "Elm.Kernel.List.indexedMap",
        args: [
          %{
            op: :lambda,
            args: ["i", "value"],
            body: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :eq,
                left: %{op: :var, name: "i"},
                right: %{op: :var, name: "index"}
              },
              then_expr: %{op: :var, name: "newValue"},
              else_expr: %{op: :var, name: "value"}
            }
          },
          %{op: :var, name: "cells"}
        ]
      }
    }

    assert {:ok, %{fusion_c: fusion}} = ListIndexedReplace.try_plan("Main", decl, %{}, [])
    assert fusion =~ "elmc_list_replace_nth_int"
  end

  test "ListIndexedReplace direct wrapper peels boxed Int args into _native" do
    decl = %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :qualified_call,
        target: "Elm.Kernel.List.indexedMap",
        args: [
          %{
            op: :lambda,
            args: ["i", "value"],
            body: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :eq,
                left: %{op: :var, name: "i"},
                right: %{op: :var, name: "index"}
              },
              then_expr: %{op: :var, name: "newValue"},
              else_expr: %{op: :var, name: "value"}
            }
          },
          %{op: :var, name: "cells"}
        ]
      }
    }

    decl_map = %{{"Main", "setCell"} => decl}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "setCell"}]))

    assert {:ok, _plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    c =
      FunctionEmit.emit_function_def(
        decl,
        "Main",
        Util.module_fn_name("Main", "setCell"),
        %{},
        decl_map,
        false
      )

    assert c =~ "elmc_fn_Main_setCell_native(ElmcValue **out, const elmc_int_t index"
    assert c =~ "ElmcValue *index"
    assert c =~ "Rc = elmc_fn_Main_setCell_native(out, elmc_as_int(index), elmc_as_int(newValue), cells);"
  end

  test "ListIndexedReplace recognizes curried indexedMap lambda" do
    decl = %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      expr: %{
        op: :qualified_call,
        target: "List.indexedMap",
        args: [
          %{
            op: :lambda,
            args: ["i"],
            body: %{
              op: :lambda,
              args: ["value"],
              body: %{
                op: :if,
                cond: %{
                  op: :compare,
                  kind: :eq,
                  left: %{op: :var, name: "i"},
                  right: %{op: :var, name: "index"}
                },
                then_expr: %{op: :var, name: "newValue"},
                else_expr: %{op: :var, name: "value"}
              }
            }
          },
          %{op: :var, name: "cells"}
        ]
      }
    }

    assert {:ok, %{fusion_c: fusion}} = ListIndexedReplace.try_plan("Main", decl, %{}, [])
    assert fusion =~ "elmc_list_replace_nth_int"
  end

  test "ListIntSearch recognizes __sub__ and __add__ recurse operands" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl_map = %{
      {"Main", "nthEmptyIndexHelp"} => %{
        name: "nthEmptyIndexHelp",
        args: ["target", "index", "cells"],
        type: "Int -> Int -> List Int -> Int"
      }
    }

    decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      expr: %{
        op: :case,
        subject: %{op: :var, name: "cells"},
        branches: [
          %{pattern: %{kind: :constructor, name: "[]"}, expr: %{op: :int_literal, value: -1}},
          %{
            pattern: cons.(%{kind: :var, name: "value"}, %{kind: :var, name: "rest"}),
            expr: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :eq,
                left: %{op: :var, name: "value"},
                right: %{op: :int_literal, value: 0}
              },
              then_expr: %{
                op: :if,
                cond: %{
                  op: :compare,
                  kind: :eq,
                  left: %{op: :var, name: "target"},
                  right: %{op: :int_literal, value: 0}
                },
                then_expr: %{op: :var, name: "index"},
                else_expr: %{
                  op: :qualified_call,
                  target: "Main.nthEmptyIndexHelp",
                  args: [
                    %{op: :call, name: "__sub__", args: [%{op: :var, name: "target"}, %{op: :int_literal, value: 1}]},
                    %{op: :call, name: "__add__", args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 1}]},
                    %{op: :var, name: "rest"}
                  ]
                }
              },
              else_expr: %{
                op: :qualified_call,
                target: "Main.nthEmptyIndexHelp",
                args: [
                  %{op: :var, name: "target"},
                  %{op: :call, name: "__add__", args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 1}]},
                  %{op: :var, name: "rest"}
                ]
              }
            }
          }
        ]
      }
    }

    assert {:ok, %{fusion_c: fusion, native_scalar_return: :native_int, fusion_emit: :helper_only}} =
             ListIntSearch.try_plan("Main", decl, decl_map, [])

    assert fusion =~ "list_search_head_"
    assert fusion =~ "nthEmptyIndexHelp_native"
  end

  test "ListIntSearch recognizes nthEmptyIndex delegate to fused help" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    help_decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      expr: %{
        op: :case,
        subject: %{op: :var, name: "cells"},
        branches: [
          %{pattern: %{kind: :constructor, name: "[]"}, expr: %{op: :int_literal, value: -1}},
          %{
            pattern: cons.(%{kind: :var, name: "value"}, %{kind: :var, name: "rest"}),
            expr: %{
              op: :if,
              cond: %{
                op: :compare,
                kind: :eq,
                left: %{op: :var, name: "value"},
                right: %{op: :int_literal, value: 0}
              },
              then_expr: %{
                op: :if,
                cond: %{
                  op: :compare,
                  kind: :eq,
                  left: %{op: :var, name: "target"},
                  right: %{op: :int_literal, value: 0}
                },
                then_expr: %{op: :var, name: "index"},
                else_expr: %{
                  op: :qualified_call,
                  target: "Main.nthEmptyIndexHelp",
                  args: [
                    %{
                      op: :call,
                      name: "__sub__",
                      args: [%{op: :var, name: "target"}, %{op: :int_literal, value: 1}]
                    },
                    %{
                      op: :call,
                      name: "__add__",
                      args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 1}]
                    },
                    %{op: :var, name: "rest"}
                  ]
                }
              },
              else_expr: %{
                op: :qualified_call,
                target: "Main.nthEmptyIndexHelp",
                args: [
                  %{op: :var, name: "target"},
                  %{
                    op: :call,
                    name: "__add__",
                    args: [%{op: :var, name: "index"}, %{op: :int_literal, value: 1}]
                  },
                  %{op: :var, name: "rest"}
                ]
              }
            }
          }
        ]
      }
    }

    delegate_decl = %{
      name: "nthEmptyIndex",
      args: ["target", "cells"],
      type: "Int -> List Int -> Int",
      expr: %{
        op: :qualified_call,
        target: "Main.nthEmptyIndexHelp",
        args: [
          %{op: :var, name: "target"},
          %{op: :int_literal, value: 0},
          %{op: :var, name: "cells"}
        ]
      }
    }

    decl_map = %{
      {"Main", "nthEmptyIndexHelp"} => help_decl,
      {"Main", "nthEmptyIndex"} => delegate_decl
    }

    assert {:ok, %{fusion_c: fusion, native_scalar_return: :native_int, native_scalar_value_return: true, fusion_emit: :public_native}} =
             ListIntSearch.try_plan("Main", delegate_decl, decl_map, [])

    assert fusion =~ "nthEmptyIndexHelp_native"
    assert fusion =~ "static elmc_int_t elmc_fn_Main_nthEmptyIndex("
    refute fusion =~ "elmc_fn_Main_nthEmptyIndex_native("
    refute fusion =~ "elmc_fn_Main_nthEmptyIndexHelp("
  end
end
