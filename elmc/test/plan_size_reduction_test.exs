defmodule Elmc.PlanSizeReductionTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.C.Lower.Instr
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.TestSupport.TemplateCompile

  test "render_cmd lowers to elmc_render_cmd6_take in RC mode" do
    decl = %{
      name: "cmd",
      args: [],
      expr: %{
        op: :render_cmd,
        kind: %{op: :c_int_expr, value: "ELMC_RENDER_OP_RECT"},
        params: [
          %{op: :int_literal, value: 1},
          %{op: :int_literal, value: 2},
          %{op: :int_literal, value: 3},
          %{op: :int_literal, value: 4}
        ]
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_render_cmd6_take"
    refute c =~ "elmc_render_cmd6("
  end

  test "render_text_cmd lowers to elmc_render_text_cmd_take with native int params" do
    decl = %{
      name: "text_cmd",
      args: [],
      expr: %{
        op: :render_text_cmd,
        kind: %{op: :c_int_expr, value: "ELMC_RENDER_OP_TEXT"},
        int_params: [
          %{op: :int_literal, value: 1},
          %{op: :int_literal, value: 4},
          %{op: :int_literal, value: 4},
          %{op: :int_literal, value: 132},
          %{op: :int_literal, value: 16},
          %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_CENTER"}
        ],
        text: %{op: :string_literal, value: "2048"}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_render_text_cmd_take"
    refute c =~ "elmc_tuple2("
    refute c =~ "elmc_new_int(&"
  end

  test "tuple2 of int literals uses elmc_tuple2_ints" do
    decl = %{
      name: "pair",
      args: [],
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple2("
  end

  test "tuple2_ints in non-RC functions uses take_value wrapper" do
    decl = %{
      name: "pair",
      args: [],
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Pebble.Ui", %{}, rc_required: false)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_tuple2_ints_take_value"
    refute c =~ "elmc_tuple2_ints(1"
  end

  test "truthy phi merge uses native bool without boxing arms" do
    decl = %{
      name: "pick",
      args: ["n"],
      expr: %{
        op: :let_in,
        name: "guard",
        value_expr: %{
          op: :if,
          cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 0}},
          then_expr: %{op: :int_literal, value: 1},
          else_expr: %{
            op: :compare,
            kind: :eq,
            left: %{op: :var, name: "n"},
            right: %{op: :int_literal, value: 0}
          }
        },
        in_expr: %{
          op: :if,
          cond: %{op: :var, name: "guard"},
          then_expr: %{op: :int_literal, value: 0},
          else_expr: %{op: :int_literal, value: 42}
        }
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "plan_native_bool_"
    assert c =~ "? true :"
    refute Regex.match?(~r/elmc_plan_block_\d+:\s*\n\s*elmc_plan_block_\d+:/, c)
    refute c =~ "elmc_new_bool(&"
    refute c =~ "elmc_as_bool(owned"
  end

  test "phi merge into dead owned slot transfers without retain or release guard" do
    decl = %{
      name: "pick",
      args: ["flag"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    refute c =~ ~r/if \(owned\[\d+\] && owned\[\d+\] != owned\[\d+\]\)/
    refute c =~ ~r/owned\[\d+\] = elmc_retain\(owned\[\d+\]\);\n\s*elmc_plan_block_/
  end

  test "List.range |> List.map uses list_cursor_map loop" do
    decl = %{
      name: "rows",
      args: [],
      expr: %{
        op: :qualified_call,
        target: "List.map",
        args: [
          %{op: :lambda, args: ["i"], body: %{op: :int_literal, value: 0}},
          %{
            op: :qualified_call,
            target: "List.range",
            args: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 3}]
          }
        ]
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Grid", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "list_map_cursor_i_"
    refute c =~ "elmc_list_map"
  end

  test "advanceSeed lowers to native int return without boxing" do
    decl = %{
      name: "advanceSeed",
      args: ["seed"],
      type: "Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :call,
        name: "modBy",
        args: [
          %{op: :int_literal, value: 2_147_483_647},
          %{
            op: :call,
            name: "__add__",
            args: [
              %{
                op: :call,
                name: "__mul__",
                args: [%{op: :var, name: "seed"}, %{op: :int_literal, value: 16_807}]
              },
              %{op: :int_literal, value: 11}
            ]
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "advanceSeed"} => decl})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    assert plan.native_scalar_return == :native_int
    assert plan.native_scalar_value_return
    c = CLowerFunction.emit(plan)
    assert c =~ "return "
    refute c =~ "elmc_new_int(&"
    refute c =~ "plan_native_int_"
    refute c =~ "2147483647 == 0"
    refute c =~ "2147483647 < 0"
    refute c =~ "RC Rc"
    refute c =~ "CATCH_BEGIN"
    assert c =~ "seed * 16807"
    assert c =~ "+ 11"
    assert c =~ "% 2147483647"
  end

  test "randomIndex lowers to native int return with native int phi" do
    decl = %{
      name: "randomIndex",
      args: ["maxExclusive", "seed"],
      type: "Int -> Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :if,
        cond: %{
          op: :compare,
          kind: :le,
          left: %{op: :var, name: "maxExclusive"},
          right: %{op: :int_literal, value: 0}
        },
        then_expr: %{op: :int_literal, value: 0},
        else_expr: %{
          op: :call,
          name: "modBy",
          args: [%{op: :var, name: "maxExclusive"}, %{op: :var, name: "seed"}]
        }
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "randomIndex"} => decl})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    assert plan.native_scalar_return == :native_int
    assert plan.native_scalar_value_return
    c = CLowerFunction.emit(plan)
    assert c =~ "plan_native_bool_"
    assert c =~ "return "
    refute c =~ "*out = "
    refute c =~ "elmc_plan_block_2"
    refute c =~ "ElmcValue *owned"
    refute c =~ "owned[0] ="
    assert c =~ "plan_native_bool_3"
  end

  test "Program-return main tails literal int into out without owned slot" do
    decl = %{
      name: "main",
      args: [],
      type: "Program",
      expr: %{op: :int_literal, value: 0}
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    refute plan.native_scalar_return
    c = CLowerFunction.emit(plan)
    refute c =~ "arg0"
    assert c =~ "Rc = elmc_new_int(out, 0);"
    refute c =~ "ElmcValue *owned"
    refute c =~ "*out = owned["
  end

  test "countEmpty plan primary lowers to native int return without float dispatch" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl = %{
      name: "countEmpty",
      args: ["cells"],
      type: "List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "cells"},
        branches: [
          %{pattern: %{kind: :constructor, name: "[]"}, expr: %{op: :int_literal, value: 0}},
          %{
            pattern: cons.(%{kind: :var, name: "value"}, %{kind: :var, name: "rest"}),
            expr: %{
              op: :call,
              name: "__add__",
              args: [
                %{
                  op: :if,
                  cond: %{
                    op: :compare,
                    kind: :eq,
                    left: %{op: :var, name: "value"},
                    right: %{op: :int_literal, value: 0}
                  },
                  then_expr: %{op: :int_literal, value: 1},
                  else_expr: %{op: :int_literal, value: 0}
                },
                %{op: :qualified_call, target: "Main.countEmpty", args: [%{op: :var, name: "rest"}]}
              ]
            }
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "countEmpty"} => decl})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{{"Main", "countEmpty"} => decl}, rc_required: true)
    assert plan.native_scalar_return == :native_int
    refute Map.get(plan, :native_scalar_value_return)

    c = CLowerFunction.emit(plan)

    count_fn = c

    refute count_fn =~ "ELMC_TAG_FLOAT"
    refute count_fn =~ "elmc_new_float"
    refute count_fn =~ "plan_call_int_"
    refute count_fn =~ ~r/owned\[\d+\] = elmc_list_head\([^;]+\);\s*if \(!owned/
    assert count_fn =~ "elmc_fn_Main_countEmpty(&plan_native_int_"
    refute count_fn =~ ~r/elmc_fn_Main_countEmpty\(&plan_native_int_\d+, elmc_as_int\(/
    refute count_fn =~ ~r/elmc_new_int\(&owned\[\d+\], plan_native_int_\d+ \+ plan_native_int_/
    assert count_fn =~ ~r/plan_native_int_\d+ = plan_native_int_\d+ \+ plan_native_int_\d+/
    refute count_fn =~ ~r/elmc_plan_block_\d+:\s*\n\s*elmc_plan_block_\d+:/
    assert count_fn =~ "elmc_list_is_empty(cells)"
    assert count_fn =~ "elmc_list_head_with_default_int"
    refute count_fn =~ "elmc_int_list_head_boxed"
    refute count_fn =~ ~r/elmc_as_int\(owned\[\d+\]\) == 0/
    assert count_fn =~ "*out = "
  end

  test "native int param keeps C name when also used boxed in tuple2" do
    advance_decl = %{
      name: "advanceSeed",
      args: ["seed"],
      type: "Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :call,
        name: "__add__",
        args: [
          %{
            op: :call,
            name: "__mul__",
            args: [%{op: :var, name: "seed"}, %{op: :int_literal, value: 16_807}]
          },
          %{op: :int_literal, value: 11}
        ]
      }
    }

    decl = %{
      name: "advanceAndPair",
      args: ["seed"],
      type: "Int -> ( Int, Int )",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :qualified_call, target: "Main.advanceSeed", args: [%{op: :var, name: "seed"}]},
        right: %{op: :var, name: "seed"}
      }
    }

    decl_map = %{
      {"Main", "advanceSeed"} => advance_decl,
      {"Main", "advanceAndPair"} => decl
    }

    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_program_decls, decl_map)

    assert {:ok, advance_plan} = PlanLower.lower(advance_decl, "Main", decl_map, rc_required: true)
    assert advance_plan.native_scalar_value_return

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    refute c =~ "arg0"
    assert c =~ "plan_native_int_"
    assert c =~ "= elmc_fn_Main_advanceSeed(seed)"
    refute c =~ "elmc_fn_Main_advanceSeed(&plan_native_int_"
  end

  test "advanceSeed full emit uses value-return C signature" do
    advance_decl = %{
      name: "advanceSeed",
      args: ["seed"],
      type: "Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :call,
        name: "modBy",
        args: [
          %{op: :int_literal, value: 2_147_483_647},
          %{
            op: :call,
            name: "__add__",
            args: [
              %{
                op: :call,
                name: "__mul__",
                args: [%{op: :var, name: "seed"}, %{op: :int_literal, value: 16_807}]
              },
              %{op: :int_literal, value: 11}
            ]
          }
        ]
      }
    }

    decl_map = %{{"Main", "advanceSeed"} => advance_decl}
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} = PlanLower.lower(advance_decl, "Main", decl_map, rc_required: true)
    assert plan.native_scalar_value_return

    body =
      Elmc.Backend.CCodegen.FunctionEmit.emit_function_def(
        advance_decl,
        "Main",
        Elmc.Backend.CCodegen.Util.module_fn_name("Main", "advanceSeed"),
        %{},
        decl_map,
        false
      )

    assert body =~ "static elmc_int_t elmc_fn_Main_advanceSeed(elmc_int_t seed)"
    refute body =~ "static RC elmc_fn_Main_advanceSeed"
    assert body =~ "return "
    refute body =~ "elmc_new_int"
  end

  @tag :slow
  test "spawnTileWithSeed avoids native int ping-pong boxing between native callees" do
    uid = System.unique_integer([:positive])
    project_dir = Path.expand("tmp/spawn_tile_native_int_#{uid}", __DIR__)
    out_dir = Path.expand("tmp/spawn_tile_native_int_out_#{uid}", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "static RC elmc_fn_Main_spawnTileWithSeed"

    spawn_fn =
      case Regex.run(
             ~r/static RC elmc_fn_Main_spawnTileWithSeed\(ElmcValue \*\*out, elmc_int_t seed, ElmcValue \*cells\) \{[\s\S]*?\n\}/,
             generated_c
           ) do
        [fn_text] -> fn_text
        _ -> flunk("spawnTileWithSeed plan body not found in generated C")
      end

    refute spawn_fn =~ "plan_call_int_"
    refute spawn_fn =~ ~r/elmc_fn_Main_advanceSeed\([^;]+;\s*CHECK_RC\(Rc\);\s*Rc = elmc_new_int/
    refute spawn_fn =~ ~r/elmc_fn_Main_randomIndex\([^;]+;\s*CHECK_RC\(Rc\);\s*Rc = elmc_new_int/
    assert spawn_fn =~ "elmc_fn_Main_countEmpty(&plan_native_int_"
    refute spawn_fn =~ "elmc_list_repeat("
  end

  test "emptyBoard List.repeat 16 0 folds to elmc_list_from_int_array with direct fn_out" do
    decl = %{
      name: "emptyBoard",
      args: [],
      type: "List Int",
      expr: %{
        op: :call,
        target: "List.repeat",
        args: [%{op: :int_literal, value: 16}, %{op: :int_literal, value: 0}]
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_list_from_int_array(out,"
    refute c =~ "elmc_list_from_int_array(&owned["
    refute c =~ "*out = owned["
    refute c =~ "ElmcValue *owned"
    refute c =~ "elmc_list_repeat"
    refute c =~ "elmc_new_int(&owned[0], 16)"
  end

  test "tuple2 function tail writes elmc_tuple2 directly to out" do
    decl = %{
      name: "init",
      args: [],
      type: "( Model, Cmd Msg )",
      expr: %{
        op: :tuple2,
        left: %{
          op: :record_literal,
          name: "Model",
          fields: [%{name: "board", value: %{op: :int_literal, value: 0}}]
        },
        right: %{op: :cmd_none}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "Rc = elmc_tuple2(out,"
    refute c =~ ~r/\*out = owned\[\d+\];/
  end

  test "non-RC ElmcValue star return uses return not out pointer" do
    decl = %{
      name: "windowStack",
      args: ["windows"],
      type: "List Ui.Window -> Ui.UiNode",
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{op: :var, name: "windows"}
      }
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Pebble.Ui", %{}, rc_required: false)
    refute plan.rc_required
    c = CLowerFunction.emit(plan)

    assert c =~ "return elmc_tuple2_ints_take_value(1, elmc_as_int(windows))"
    refute c =~ "ElmcValue *owned"
    refute c =~ "*out"
    refute c =~ "ElmcValue **out"
  end

  test "nthEmptyIndex thin delegate tails Help into out with direct borrow params" do
    help_decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: -1},
        right: %{op: :int_literal, value: 0}
      }
    }

    decl = %{
      name: "nthEmptyIndex",
      args: ["target", "cells"],
      type: "Int -> List Int -> Int",
      ownership: [:borrow_arg, :retain_result],
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
      {"Main", "nthEmptyIndex"} => decl
    }

    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    Process.put(:elmc_rc_required, MapSet.new([{"Main", "nthEmptyIndex"}, {"Main", "nthEmptyIndexHelp"}]))
    Process.put(:elmc_program_decls, decl_map)

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "Rc = elmc_fn_Main_nthEmptyIndexHelp(out, target, 0, cells);"
    refute c =~ "ElmcValue *owned"
    refute c =~ "owned[0] = cells"
    refute c =~ "*out = owned"
  end

  test "boxed nthEmptyIndexHelp empty branch materializes -1 instead of arg reg refs" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "cells"},
        branches: [
          %{pattern: %{kind: :constructor, name: "[]"}, expr: %{op: :int_literal, value: -1}},
          %{
            pattern: cons.(%{kind: :var, name: "value"}, %{kind: :var, name: "rest"}),
            expr: %{op: :var, name: "index"}
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "nthEmptyIndexHelp"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{{"Main", "nthEmptyIndexHelp"} => decl}, rc_required: true)
    refute plan.native_scalar_return == :native_int

    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_new_int(&owned"
    assert c =~ "-1)"
    refute c =~ "arg4"
    refute c =~ "elmc_retain(arg"
  end

  test "List Int case cons peels head and tail without Maybe payload" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl = %{
      name: "countEmpty",
      args: ["cells"],
      type: "List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "cells"},
        branches: [
          %{pattern: %{kind: :constructor, name: "[]"}, expr: %{op: :int_literal, value: 0}},
          %{
            pattern: cons.(%{kind: :var, name: "value"}, %{kind: :var, name: "rest"}),
            expr: %{op: :var, name: "value"}
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "countEmpty"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{{"Main", "countEmpty"} => decl}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_list_head_with_default_int"
    assert c =~ "elmc_int_list_tail"
    refute c =~ "elmc_int_list_head_boxed"
    refute c =~ "elmc_maybe_just_payload"
  end

  test "main literal int tails elmc_new_int into out without owned array" do
    decl = %{
      name: "main",
      args: [],
      type: "Program",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{op: :int_literal, value: 0}
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "Rc = elmc_new_int(out, 0);"
    refute c =~ "ElmcValue *owned"
    refute c =~ "*out = owned"
  end

  test "non-RC Ui window tuple tail returns without owned scratch" do
    decl = %{
      name: "window",
      args: ["id", "layers"],
      type: "Int -> List LayerNode -> WindowNode",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :tuple2,
        left: %{op: :int_literal, value: 1},
        right: %{
          op: :tuple2,
          left: %{op: :var, name: "id"},
          right: %{op: :var, name: "layers"}
        }
      }
    }

    Process.put(:elmc_program_decls, %{{"Pebble.Ui", "window"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, plan} = PlanLower.lower(decl, "Pebble.Ui", %{{"Pebble.Ui", "window"} => decl}, rc_required: false)
    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_tuple2_take_value"
    assert c =~ "elmc_tuple2_ints_take_value(elmc_as_int(id), elmc_as_int(layers))"
    refute c =~ "ElmcValue *owned["
    refute c =~ "return __ret"
  end

  test "elm_mod_by_c_expr folds known non-zero divisor" do
    assert Instr.elm_mod_by_c_expr("2147483647", "x") =~ "__elmc_mod_v % 2147483647"
    refute Instr.elm_mod_by_c_expr("2147483647", "x") =~ "2147483647 == 0"
    refute Instr.elm_mod_by_c_expr("2147483647", "x") =~ "2147483647 < 0"
    refute Instr.elm_mod_by_c_expr("2147483647", "x") =~ ~r/^\{ /
    assert Instr.elm_mod_by_c_expr("0", "x") == "0"
  end

  test "setCell plan fusion lowers indexedMap replace to elmc_list_replace_nth_int" do
    decl = %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :qualified_call,
        target: "List.indexedMap",
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

    Process.put(:elmc_program_decls, %{{"Main", "setCell"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, %{fusion_c: fusion}} = PlanLower.lower(decl, "Main", %{{"Main", "setCell"} => decl}, rc_required: true)
    assert fusion =~ "elmc_list_replace_nth_int"
    refute fusion =~ "elmc_list_indexed_map"
    refute fusion =~ "setCell_closure"
  end

  test "setCell plan fusion accepts Elm.Kernel.List.indexedMap target" do
    decl = %{
      name: "setCell",
      args: ["index", "newValue", "cells"],
      type: "Int -> Int -> List Int -> List Int",
      ownership: [:borrow_arg, :borrow_result],
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

    assert {:ok, %{fusion_c: fusion}} =
             PlanLower.lower(decl, "Main", %{{"Main", "setCell"} => decl}, rc_required: true)

    assert fusion =~ "elmc_list_replace_nth_int"
    refute fusion =~ "elmc_list_indexed_map"
  end

  test "nthEmptyIndexHelp plan fusion emits native int list search loop" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
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
                    %{op: :sub_const, var: "target", value: 1},
                    %{op: :add_const, var: "index", value: 1},
                    %{op: :var, name: "rest"}
                  ]
                }
              },
              else_expr: %{
                op: :qualified_call,
                target: "Main.nthEmptyIndexHelp",
                args: [
                  %{op: :var, name: "target"},
                  %{op: :add_const, var: "index", value: 1},
                  %{op: :var, name: "rest"}
                ]
              }
            }
          }
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "nthEmptyIndexHelp"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

    assert {:ok, %{fusion_c: fusion, native_scalar_return: :native_int}} =
             PlanLower.lower(decl, "Main", %{{"Main", "nthEmptyIndexHelp"} => decl}, rc_required: true)

    assert fusion =~ "list_search_head_"
    assert fusion =~ "nthEmptyIndexHelp_native"
    refute fusion =~ "elmc_maybe_just_payload"
  end

  test "nthEmptyIndexHelp plan fusion accepts __sub__ and __add__ recurse operands" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    decl = %{
      name: "nthEmptyIndexHelp",
      args: ["target", "index", "cells"],
      type: "Int -> Int -> List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
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

    assert {:ok, %{fusion_c: fusion, native_scalar_return: :native_int}} =
             PlanLower.lower(decl, "Main", %{{"Main", "nthEmptyIndexHelp"} => decl}, rc_required: true)

    assert fusion =~ "list_search_head_"
    assert fusion =~ "nthEmptyIndexHelp_native"
  end

  test "size profile emits switch(state) loop for multi-block plan functions" do
    decl = %{
      name: "branchy",
      args: ["n"],
      expr: %{
        op: :if,
        cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 0}},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{
          op: :if,
          cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 10}},
          then_expr: %{op: :int_literal, value: 2},
          else_expr: %{
            op: :if,
            cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 20}},
            then_expr: %{op: :int_literal, value: 3},
            else_expr: %{
              op: :if,
              cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 30}},
              then_expr: %{op: :int_literal, value: 4},
              else_expr: %{
                op: :if,
                cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 40}},
                then_expr: %{op: :int_literal, value: 5},
                else_expr: %{
                  op: :if,
                  cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 50}},
                  then_expr: %{op: :int_literal, value: 6},
                  else_expr: %{
                    op: :if,
                    cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 60}},
                    then_expr: %{op: :int_literal, value: 7},
                    else_expr: %{op: :int_literal, value: 8}
                  }
                }
              }
            }
          }
        }
      }
    }

    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_ir_mode: :primary, plan_emit: :state_switch})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{{"Main", "branchy"} => decl}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "switch (__plan_state)"
    refute c =~ "goto elmc_plan_block_"
  end

  test "state-switch union tag dispatch uses elmc_union_tag_matches" do
    decl = %{
      name: "update",
      args: ["msg", "model"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Left", tag: 1, arg_pattern: nil},
            expr: %{op: :int_literal, value: 10}
          },
          %{
            pattern: %{kind: :constructor, name: "Right", tag: 2, arg_pattern: nil},
            expr: %{op: :int_literal, value: 20}
          },
          %{
            pattern: %{kind: :constructor, name: "Up", tag: 3, arg_pattern: nil},
            expr: %{op: :int_literal, value: 30}
          },
          %{
            pattern: %{kind: :constructor, name: "Down", tag: 4, arg_pattern: nil},
            expr: %{op: :int_literal, value: 40}
          },
          %{
            pattern: %{kind: :constructor, name: "Tick", tag: 5, arg_pattern: nil},
            expr: %{op: :int_literal, value: 50}
          },
          %{
            pattern: %{kind: :constructor, name: "Load", tag: 6, arg_pattern: %{kind: :var, name: "payload"}},
            expr: %{op: :var, name: "payload"}
          },
          %{
            pattern: %{kind: :wildcard},
            expr: %{op: :tuple2, left: %{op: :var, name: "model"}, right: %{op: :int_literal, value: 0}}
          }
        ]
      }
    }

    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_ir_mode: :primary, plan_emit: :state_switch})

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "switch (__plan_state)"
    refute c =~ "ELMC_PLAN_STATE_"
    assert c =~ "case 0:"
    refute Regex.match?(~r/\bmsg\s*==\s*\d+/, c)
    assert c =~ "elmc_union_tag_as_int(" or c =~ "ELMC_UNION_" or c =~ "ELMC_TAG_TUPLE2"
    refute Regex.match?(~r/switch \([^)]+\) \{\s*case \d+: __plan_state = \d+; break;\s*\}\s*case \d+:/s, c)
    refute Regex.match?(~r/enum \{\s*\d+\s*=\s*\d+,/m, c)
    refute c =~ "goto elmc_plan_block_"
  end

  test "state-switch moveBoard uses module-qualified direction macros for ambiguous Up/Down" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("game_2048",
        plan_ir_mode: :primary,
        plan_ir_strict: false,
        out_dir: Path.expand("tmp/plan_2048_tag_refs", __DIR__)
      )

    decl_map = TemplateCompile.decl_map_from_result(result)
    {_defines, macros} = UnionMacros.definitions(result.ir)

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))
    Process.put(:elmc_union_constructor_macros, macros)
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_ir_mode: :primary, plan_emit: :state_switch})

    decl = Map.fetch!(decl_map, {"Main", "update"})
    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert c =~ "ELMC_UNION_MAIN_UP"
    assert c =~ "ELMC_UNION_MAIN_DOWN"
    refute c =~ "moveBoard_native(&owned[3], 3, model)"
    refute c =~ "moveBoard_native(&owned[3], 4, model)"
  end

  test "size profile state_switch uses compact numeric plan states" do
    decl = %{
      name: "branchy",
      args: ["n"],
      expr: %{
        op: :if,
        cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 10}},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{
          op: :if,
          cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 20}},
          then_expr: %{op: :int_literal, value: 2},
          else_expr: %{
            op: :if,
            cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 30}},
            then_expr: %{op: :int_literal, value: 3},
            else_expr: %{
              op: :if,
              cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 40}},
              then_expr: %{op: :int_literal, value: 4},
              else_expr: %{
                op: :if,
                cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 50}},
                then_expr: %{op: :int_literal, value: 5},
                else_expr: %{
                  op: :if,
                  cond: %{op: :compare, kind: :lt, left: %{op: :var, name: "n"}, right: %{op: :int_literal, value: 60}},
                  then_expr: %{op: :int_literal, value: 6},
                  else_expr: %{op: :int_literal, value: 7}
                }
              }
            }
          }
        }
      }
    }

    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_emit: :state_switch})

    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)

    assert {:ok, plan} = PlanLower.lower(decl, "Main", %{{"Main", "branchy"} => decl}, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "switch (__plan_state)"
    refute c =~ "ELMC_PLAN_STATE_"
    refute c =~ "enum {"
    assert c =~ "case 0:"
  end

  test "read-only retain_arg params pass C argument without retain copy" do
    score_of = %{
      name: "scoreOf",
      args: ["model"],
      ownership: [:borrow_arg],
      expr: %{
        op: :field_access,
        arg: %{op: :var, name: "model"},
        field: "score"
      }
    }

    decl = %{
      name: "view",
      args: ["model"],
      ownership: [:retain_arg, :retain_result],
      expr: %{
        op: :call,
        name: "scoreOf",
        args: [%{op: :var, name: "model"}]
      }
    }

    decl_map = %{
      {"Main", "scoreOf"} => score_of,
      {"Main", "view"} => decl
    }

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_fn_Main_scoreOf(out, model)"
    refute c =~ "elmc_retain(model)"
  end

  test "cross-block borrow param calls pass C argument without duplicate retain" do
    score_of = %{
      name: "scoreOf",
      args: ["model"],
      ownership: [:borrow_arg],
      expr: %{
        op: :field_access,
        arg: %{op: :var, name: "model"},
        field: "score"
      }
    }

    decl = %{
      name: "view",
      args: ["model"],
      ownership: [:borrow_arg],
      expr: %{
        op: :if,
        cond: %{
          op: :compare,
          kind: :eq,
          left: %{
            op: :field_access,
            arg: %{op: :var, name: "model"},
            field: "score"
          },
          right: %{op: :int_literal, value: 0}
        },
        then_expr: %{
          op: :call,
          name: "scoreOf",
          args: [%{op: :var, name: "model"}]
        },
        else_expr: %{
          op: :call,
          name: "scoreOf",
          args: [%{op: :var, name: "model"}]
        }
      }
    }

    decl_map = %{
      {"Main", "scoreOf"} => score_of,
      {"Main", "view"} => decl
    }

    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_record_alias_shapes, %{{"Main", "Model"} => ["score"]})

    on_exit(fn ->
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_record_alias_shapes)
    end)

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)
    c = CLowerFunction.emit(plan)
    assert length(Regex.scan(~r/elmc_fn_Main_scoreOf\([^)]*model\)/, c)) >= 2
    refute c =~ "elmc_retain(model)"
  end

  test "fused native plan bodies skip state-switch emit" do
    plan = %Elmc.Backend.Plan.Types.FunctionPlan{
      module: "Main",
      name: "fusedNative",
      params: ["board"],
      rc_required: true,
      fusion_c: """
      static RC elmc_fn_Main_fusedNative_native(ElmcValue **out, ElmcValue *board) {
        RC Rc = RC_SUCCESS;
        CATCH_BEGIN
        Rc = elmc_new_int(out, 1);
        CHECK_RC(Rc);
        CATCH_END
        return Rc;
      }
      """,
      blocks: [
        %Elmc.Backend.Plan.Types.Block{id: 0, instrs: [], terminator: {:ret, :fn_out}}
      ],
      lambdas: []
    }

    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_emit: :state_switch})
    c = CLowerFunction.emit(plan)
    refute c =~ "switch (__plan_state)"
    assert c =~ "fusedNative_native"
  end
end
