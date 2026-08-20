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
    # Pack must take ownership of dual-out list + boxed int (not retain+orphan).
    assert c =~ "elmc_tuple2_take"
    refute c =~ ~r/elmc_tuple2\(&?plan_list_int_pair_|elmc_tuple2\(out/
    assert c =~ "plan_list_int_pair_"
  end

  test "caller of native_list_int_pair SROAs into record_update without heap pack" do
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

    apply_pair = %{
      name: "applyPair",
      args: ["model", "cells", "seed"],
      type: "Model -> List Int -> Int -> Model",
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
          op: :record_update,
          base: %{op: :var, name: "model"},
          fields: [
            %{
              field: "cells",
              expr: %{op: :tuple_first_expr, arg: %{op: :var, name: "p"}}
            },
            %{
              field: "seed",
              expr: %{op: :tuple_second_expr, arg: %{op: :var, name: "p"}}
            }
          ]
        }
      }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "applyPair"} => apply_pair}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "mk"}, {"Main", "applyPair"}]))

    # Lower the caller first so SROA must use the declared return type when the
    # callee has not been annotated into NativeReturn's cache yet.
    assert {:ok, plan} = PlanLower.lower(apply_pair, "Main", decl_map, rc_required: true)
    assert {:ok, _} = PlanLower.lower(pair, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "plan_list_int_pair_"
    assert c =~ "elmc_record_update_index_cow(out, model,"
    assert c =~ "elmc_record_update_index_int_cow_drop"
    refute c =~ "elmc_tuple2"
    refute c =~ "elmc_tuple_first"
    refute c =~ "elmc_tuple_second"
    # Call-arg Int boxing for `mk` may remain; the dual-out result must not re-box.
    refute c =~ ~r/elmc_new_int\(&plan_list_int_pair_\d+_int_box/
  end

  test "pattern-bound let (list, int) from native_list_int_pair SROAs into record_update" do
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

    apply_pair = %{
      name: "applyPair",
      args: ["model", "cells", "seed"],
      type: "Model -> List Int -> Int -> Model",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :let_in,
        name: "ignored",
        value_expr: %{
          op: :qualified_call,
          target: "Main.mk",
          args: [%{op: :var, name: "cells"}, %{op: :var, name: "seed"}]
        },
        # Simulate `let (cells2, seed2) = mk … in { model | cells = cells2, seed = seed2 }`
        # via explicit tuple projs bound through named lets (pattern-bind shape).
        in_expr: %{
          op: :let_in,
          name: "cells2",
          value_expr: %{
            op: :tuple_first_expr,
            arg: %{op: :var, name: "ignored"}
          },
          in_expr: %{
            op: :let_in,
            name: "seed2",
            value_expr: %{
              op: :tuple_second_expr,
              arg: %{op: :var, name: "ignored"}
            },
            in_expr: %{
              op: :record_update,
              base: %{op: :var, name: "model"},
              fields: [
                %{field: "cells", expr: %{op: :var, name: "cells2"}},
                %{field: "seed", expr: %{op: :var, name: "seed2"}}
              ]
            }
          }
        }
      }
    }

    decl_map = %{{"Main", "mk"} => pair, {"Main", "applyPair"} => apply_pair}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "mk"}, {"Main", "applyPair"}]))

    assert {:ok, plan} = PlanLower.lower(apply_pair, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_record_update_index_int_cow_drop"
    refute c =~ "elmc_tuple2"
    refute c =~ "elmc_tuple_first"
    refute c =~ ~r/elmc_new_int\(&plan_list_int_pair_\d+_int_box/
  end

  test "list_int_pair SROA int reg does not collide with CommonConstCallArms shared tag" do
    # Regression: Tuple2IntsUnbox allocated a dual-out int reg without bumping
    # plan.reg_count; CommonConstCallArms then reused that reg for the shared
    # direction tag, so moveBoard read plan_list_int_pair_*_int.
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

    apply_dir = %{
      name: "applyDir",
      args: ["tag", "model"],
      type: "Int -> Model -> Model",
      ownership: [:borrow_arg, :retain_result],
      expr: %{op: :var, name: "model"}
    }

    update = %{
      name: "update",
      args: ["msg", "model", "cells", "seed"],
      type: "Msg -> Model -> List Int -> Int -> Model",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Left", tag: 1, arg_pattern: nil},
            expr: %{
              op: :qualified_call,
              target: "Main.applyDir",
              args: [
                %{op: :int_literal, value: 10, union_ctor: "Main.DirLeft"},
                %{op: :var, name: "model"}
              ]
            }
          },
          %{
            pattern: %{kind: :constructor, name: "Right", tag: 2, arg_pattern: nil},
            expr: %{
              op: :qualified_call,
              target: "Main.applyDir",
              args: [
                %{op: :int_literal, value: 20, union_ctor: "Main.DirRight"},
                %{op: :var, name: "model"}
              ]
            }
          },
          %{
            pattern: %{kind: :constructor, name: "Seeded", tag: 3, arg_pattern: nil},
            expr: %{
              op: :let_in,
              name: "p",
              value_expr: %{
                op: :qualified_call,
                target: "Main.mk",
                args: [%{op: :var, name: "cells"}, %{op: :var, name: "seed"}]
              },
              in_expr: %{
                op: :record_update,
                base: %{op: :var, name: "model"},
                fields: [
                  %{
                    field: "cells",
                    expr: %{op: :tuple_first_expr, arg: %{op: :var, name: "p"}}
                  },
                  %{
                    field: "seed",
                    expr: %{op: :tuple_second_expr, arg: %{op: :var, name: "p"}}
                  }
                ]
              }
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :var, name: "model"}}
        ]
      }
    }

    decl_map = %{
      {"Main", "mk"} => pair,
      {"Main", "applyDir"} => apply_dir,
      {"Main", "update"} => update
    }

    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_constructor_tags, %{
      "Left" => 1,
      "Right" => 2,
      "Seeded" => 3,
      "Main.DirLeft" => 10,
      "Main.DirRight" => 20
    })
    Process.put(:elmc_enum_ctors, MapSet.new(["Main.DirLeft", "Main.DirRight", "DirLeft", "DirRight"]))
    Process.put(:elmc_enum_types, MapSet.new(["Main.Dir", "Dir"]))
    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new(Map.keys(decl_map)))

    assert {:ok, plan} = PlanLower.lower(update, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "plan_list_int_pair_"
    assert c =~ "elmc_record_update_index_int_cow_drop"
    assert c =~ "elmc_fn_Main_applyDir"

    # Shared direction tag must be a distinct native int, never the dual-out seed.
    refute c =~ ~r/elmc_fn_Main_applyDir\([^)]*plan_list_int_pair_\d+_int/
    assert c =~ ~r/plan_native_int_\d+\s*=/
  end
end
