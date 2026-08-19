defmodule Elmc.PlanNativeIntPairReturnTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @moduletag :plan_surface

  test "Int -> Int -> (Int, Int) uses dual out-param ABI without heap tuple in callee" do
    decl = %{
      name: "pairAdd",
      args: ["a", "b"],
      type: "Int -> Int -> ( Int, Int )",
      expr: %{
        op: :tuple2,
        left: %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: "a"}, %{op: :int_literal, value: 1}]
        },
        right: %{
          op: :call,
          name: "__add__",
          args: [%{op: :var, name: "b"}, %{op: :int_literal, value: 2}]
        }
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "pairAdd"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "pairAdd"} => decl}, rc_required: true)

    assert plan.native_scalar_return == :native_int_pair
    assert match?({_, _}, plan.native_pair_ret)
    assert NativeReturn.c_out_type(:native_int_pair) == "elmc_int_t *out0, elmc_int_t *out1"

    c = CLowerFunction.emit(plan)
    assert c =~ "*out0 ="
    assert c =~ "*out1 ="
    refute c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple2("
    # Operands must come from real values, not zero-init temps.
    refute c =~ ~r/elmc_int_t plan_native_int_\d+ = 0/
  end

  test "caller of native_int_pair skips pack when only projecting first" do
    pair = %{
      name: "mk",
      args: ["x"],
      type: "Int -> ( Int, Int )",
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "x"},
        right: %{op: :int_literal, value: 9}
      }
    }

    use_pair = %{
      name: "useMk",
      args: ["n"],
      type: "Int -> Int",
      expr: %{
        op: :call,
        name: "__add__",
        args: [
          %{
            op: :tuple_first_expr,
            arg: %{
              op: :call,
              name: "mk",
              args: [%{op: :var, name: "n"}]
            }
          },
          %{op: :int_literal, value: 1}
        ]
      }
    }

    # Prefer qualified call shape used by plan lowering.
    use_pair = %{
      use_pair
      | expr: %{
          op: :let_in,
          name: "p",
          value_expr: %{
            op: :qualified_call,
            target: "Main.mk",
            args: [%{op: :var, name: "n"}]
          },
          in_expr: %{
            op: :call,
            name: "__add__",
            args: [
              %{op: :tuple_first_expr, arg: %{op: :var, name: "p"}},
              %{op: :int_literal, value: 1}
            ]
          }
        }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "useMk"} => use_pair}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, mk_plan} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    assert mk_plan.native_scalar_return == :native_int_pair
    mk_c = CLowerFunction.emit(mk_plan)
    assert mk_c =~ "*out0 = x"
    assert mk_c =~ "*out1 = 9"

    assert {:ok, use_plan} = PlanLower.lower(use_pair, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(use_plan)
    assert c =~ "elmc_fn_Main_mk"
    assert c =~ "plan_native_pair_"
    refute c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple_first"
    assert c =~ "plan_native_pair_1_0 + 1" or c =~ "plan_native_pair_1_0+1"
    # Native Int param — caller must not box `n` for the dual-out callee.
    refute c =~ "elmc_harness_new_int(n)"
  end

  test "caller of native_int_pair packs with elmc_tuple2_ints when pair escapes" do
    pair = %{
      name: "mkEsc",
      args: ["x"],
      type: "Int -> ( Int, Int )",
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "x"},
        right: %{op: :int_literal, value: 9}
      }
    }

    use_pair = %{
      name: "returnMk",
      args: ["n"],
      type: "( Int, Int )",
      expr: %{
        op: :qualified_call,
        target: "Main.mkEsc",
        args: [%{op: :var, name: "n"}]
      }
    }

    decl_map = %{{"Main", "mkEsc"} => pair, {"Main", "returnMk"} => use_pair}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, _} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    assert {:ok, use_plan} = PlanLower.lower(use_pair, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(use_plan)
    assert c =~ "elmc_fn_Main_mkEsc"
    assert c =~ "elmc_tuple2_ints"
  end

  test "local (List, Int) pair used only via borrowed projections unboxes" do
    decl = %{
      name: "seedOf",
      args: ["cells", "seed"],
      type: "List Int -> Int -> Int",
      expr: %{
        op: :let_in,
        name: "p",
        value_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "cells"},
          right: %{op: :var, name: "seed"}
        },
        in_expr: %{
          op: :tuple_second_expr,
          arg: %{op: :var, name: "p"}
        }
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "seedOf"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "seedOf"} => decl}, rc_required: true)

    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2("
    refute c =~ "elmc_tuple_second"
  end

  test "switch arms of (Int, Int) each write dual outs" do
    decl = %{
      name: "unit4",
      args: ["index"],
      type: "Int -> ( Int, Int )",
      expr: %{
        op: :case,
        subject: %{
          op: :call,
          name: "modBy",
          args: [%{op: :int_literal, value: 4}, %{op: :var, name: "index"}]
        },
        branches: [
          %{
            pattern: %{kind: :int, value: 0},
            expr: %{
              op: :tuple2,
              left: %{op: :int_literal, value: 0},
              right: %{op: :int_literal, value: -1000}
            }
          },
          %{
            pattern: %{kind: :int, value: 1},
            expr: %{
              op: :tuple2,
              left: %{op: :int_literal, value: 1000},
              right: %{op: :int_literal, value: 0}
            }
          },
          %{
            pattern: %{kind: :wildcard},
            expr: %{
              op: :tuple2,
              left: %{op: :int_literal, value: 0},
              right: %{op: :int_literal, value: 1000}
            }
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "unit4"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "unit4"} => decl}, rc_required: true)

    assert plan.native_scalar_return == :native_int_pair
    c = CLowerFunction.emit(plan)
    assert c =~ "*out0 = 0"
    assert c =~ "*out1 = -1000"
    assert c =~ "*out0 = 1000"
    assert c =~ "*out1 = 0"
    assert c =~ "*out1 = 1000"
    refute c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple2("
  end

  test "pure Int -> (Int, Int) helper is RC-required and uses dual-out public ABI" do
    decl = %{
      name: "unitAt",
      args: ["index"],
      type: "Int -> ( Int, Int )",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "index"},
        right: %{op: :int_literal, value: 9}
      }
    }

    decl_map = %{{"Main", "unitAt"} => decl}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    RcRequired.run!(decl_map)

    assert RcRequired.rc_required?("Main", "unitAt")

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    assert plan.native_scalar_return == :native_int_pair

    c =
      FunctionEmit.emit_function_def(
        decl,
        "Main",
        Util.module_fn_name("Main", "unitAt"),
        %{},
        decl_map,
        false
      )

    assert c =~ "RC elmc_fn_Main_unitAt(elmc_int_t *out0, elmc_int_t *out1"
    refute c =~ ~r/ElmcValue \*\s*elmc_fn_Main_unitAt/
    assert c =~ "*out0 ="
    assert c =~ "*out1 = 9"
  end
end
