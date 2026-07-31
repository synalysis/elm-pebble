defmodule Elmc.PlanNativeListIntPairReturnTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @moduletag :plan_surface

  test "List Int -> Int -> (List Int, Int) uses dual-out ABI without heap tuple in callee" do
    decl = %{
      name: "consSeed",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "cells"},
        right: %{op: :var, name: "seed"}
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "consSeed"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "consSeed"}]))

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "consSeed"} => decl}, rc_required: true)

    assert plan.native_scalar_return == :native_list_int_pair
    assert NativeReturn.c_out_type(:native_list_int_pair) == "ElmcValue **out_list, elmc_int_t *out_int"

    c = CLowerFunction.emit(plan)
    assert c =~ "*out_list ="
    assert c =~ "*out_int ="
    refute c =~ "elmc_tuple2("
  end

  test "phi of (List Int, Int) arms write dual outs on each branch" do
    decl = %{
      name: "maybeReplace",
      args: ["flag", "cells", "seed"],
      type: "Bool -> List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "cells"},
          right: %{op: :var, name: "seed"}
        },
        else_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "cells"},
          right: %{
            op: :call,
            name: "__add__",
            args: [%{op: :var, name: "seed"}, %{op: :int_literal, value: 1}]
          }
        }
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "maybeReplace"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "maybeReplace"}]))

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "maybeReplace"} => decl}, rc_required: true)

    assert plan.native_scalar_return == :native_list_int_pair

    c = CLowerFunction.emit(plan)
    assert c =~ "*out_list ="
    assert c =~ "*out_int ="
    refute c =~ "elmc_tuple2("
  end

  test "passthrough caller of native_list_int_pair forwards dual outs without heap pack" do
    pair = %{
      name: "mk",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "cells"},
        right: %{op: :var, name: "seed"}
      }
    }

    use_pair = %{
      name: "useMk",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :qualified_call,
        target: "Main.mk",
        args: [%{op: :var, name: "cells"}, %{op: :var, name: "seed"}]
      }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "useMk"} => use_pair}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "mk"}, {"Main", "useMk"}]))

    assert {:ok, mk_plan} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    assert mk_plan.native_scalar_return == :native_list_int_pair

    assert {:ok, use_plan} = PlanLower.lower(use_pair, "Main", decl_map, rc_required: true)
    assert use_plan.native_scalar_return == :native_list_int_pair
    c = CLowerFunction.emit(use_plan)
    assert c =~ "elmc_fn_Main_mk"
    assert c =~ "out_list, out_int"
    refute c =~ "elmc_tuple2"
  end

  test "caller of native_list_int_pair skips pack when only projecting into next call" do
    pair = %{
      name: "mk",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "cells"},
        right: %{op: :var, name: "seed"}
      }
    }

    chain = %{
      name: "chain",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :let_in,
        name: "p",
        value_expr: %{
          op: :qualified_call,
          target: "Main.mk",
          args: [%{op: :var, name: "cells"}, %{op: :var, name: "seed"}]
        },
        in_expr: %{
          op: :qualified_call,
          target: "Main.mk",
          args: [
            %{op: :tuple_first_expr, arg: %{op: :var, name: "p"}},
            %{op: :tuple_second_expr, arg: %{op: :var, name: "p"}}
          ]
        }
      }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "chain"} => chain}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "mk"}, {"Main", "chain"}]))

    assert {:ok, _} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    assert {:ok, plan} = PlanLower.lower(chain, "Main", decl_map, rc_required: true)
    assert plan.native_scalar_return == :native_list_int_pair
    c = CLowerFunction.emit(plan)

    assert c =~ "plan_list_int_pair_"
    refute c =~ "elmc_tuple_first"
    refute c =~ "elmc_tuple_second"
    # Intermediate call-fn SROA + tail passthrough — no heap pair.
    refute c =~ "elmc_tuple2"
    assert c =~ "out_list, out_int"
  end

  test "List-returning caller is not annotated as native_list_int_pair" do
    pair = %{
      name: "mk",
      args: ["cells", "seed"],
      type: "List Int -> Int -> ( List Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :var, name: "cells"},
        right: %{op: :var, name: "seed"}
      }
    }

    use_list = %{
      name: "useList",
      args: ["cells", "seed"],
      type: "List Int -> Int -> List Int",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :let_in,
        name: "p",
        value_expr: %{
          op: :qualified_call,
          target: "Main.mk",
          args: [%{op: :var, name: "cells"}, %{op: :var, name: "seed"}]
        },
        in_expr: %{
          op: :tuple_first_expr,
          arg: %{op: :var, name: "p"}
        }
      }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "useList"} => use_list}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "mk"}, {"Main", "useList"}]))

    assert {:ok, _} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    assert {:ok, plan} = PlanLower.lower(use_list, "Main", decl_map, rc_required: true)
    refute plan.native_scalar_return == :native_list_int_pair
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_fn_Main_mk"
    # Escaping through Tuple.first still packs today (record/return peel path).
    assert c =~ "elmc_tuple_first"
  end
end
