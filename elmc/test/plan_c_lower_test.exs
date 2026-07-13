defmodule Elmc.PlanCLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.{Builder, Verify}

  test "plan lowers to RC C with CHECK_RC and owned slots" do
    b =
      Builder.new("Main", "init", args: [], rc_required: true, fallible: true)
      |> Builder.catch_begin()

    {reg, b1} = Builder.emit_const_int(b, 0)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: reg,
        args: %{builtin: :new_int, args: []},
        effects: Elmc.Backend.Plan.Types.fallible_effects(reg)
      })

    b3 =
      b2
      |> Builder.catch_end()
      |> then(fn bb ->
        bb1 = Builder.emit_ret(bb, reg)
        Builder.to_function_plan(bb1)
      end)

    assert :ok = Verify.run(b3)
    c = CLowerFunction.emit(b3)
    assert c =~ "CATCH_BEGIN"
    assert c =~ "return Rc;"
    assert c =~ "*out ="
  end

  test "companion cmd pattern lowers params to owned not out" do
    plan = Elmc.PlanFixtures.companion_send_plan()

    c = CLowerFunction.emit(plan)
    refute c =~ "watchToPhoneTag(out"
    assert c =~ "owned["
    assert c =~ "elmc_cmd2"
  end

  test "value-returning runtime builtins assign directly in RC mode" do
    plan = Elmc.PlanFixtures.companion_send_plan()
    c = CLowerFunction.emit(plan)

    refute c =~ "Rc = elmc_retain(&owned"
    refute c =~ "Rc = elmc_record_get("
  end

  test "record literal lowers to record_new_values_take in RC mode" do
    decl = %{
      name: "init",
      args: [],
      expr: %{
        op: :record_literal,
        fields: [%{name: "reading", expr: %{op: :int_literal, value: 0}}]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_record_new_values_take"
    refute c =~ "elmc_record_new_values_ints"
  end

  test "record_new nulls each consumed owned slot once" do
    decl = %{
      name: "pair",
      args: ["left", "right"],
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "x", expr: %{op: :var, name: "left"}},
          %{name: "y", expr: %{op: :var, name: "right"}}
        ]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)

    refute c =~
             ~r/elmc_record_new_values_take\(&owned\[\d+\], 2, rec_values_\d+\);\n\s*CHECK_RC\(Rc\);\n\s*owned\[\d+\] = NULL;\n\s*owned\[\d+\] = NULL;\n\s*owned\[\d+\] = NULL;/
    refute c =~ ~r/owned\[\d+\] = owned\[\d+\];\n\s*owned\[\d+\] = NULL;\n\s*\n\s*owned\[\d+\] = NULL;/
  end

  test "record update uses value-returning C calls" do
    decl = %{
      name: "bump",
      args: ["model"],
      expr: %{
        op: :record_update,
        base: %{op: :var, name: "model"},
        fields: [%{field: "reading", expr: %{op: :int_literal, value: 1}}]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_retain(model)"
    assert c =~ "elmc_record_update_index_cow_drop("
    refute c =~ "Rc = elmc_record_update_index_cow_drop("
    assert c =~ "owned[1] = NULL;"
    refute c =~ ~r/owned\[1\] = NULL;\s*elmc_release\(owned\[1\]\);\s*owned\[1\] = NULL;\s*Rc = elmc_cmd0\(&owned\[1\]/
  end

  test "record get lowers to elmc_record_get_index" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Main", "Model"} => ["board", "score", "lines"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    decl = %{
      name: "scoreOf",
      args: ["model"],
      expr: %{
        op: :field_access,
        arg: %{op: :var, name: "model"},
        field: "score"
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_record_get_index(model, 1 /* score */)"
    refute c =~ ~s/elmc_record_get(owned[0], "score")/
    refute c =~ "RC_ERR_OUT_OF_MEMORY"
  end

  test "direct value-return builtins do not emit spurious OOM null checks" do
    plan = Elmc.PlanFixtures.companion_send_plan()
    c = CLowerFunction.emit(plan)

    refute c =~ "if (!owned"
    refute c =~ "RC_ERR_OUT_OF_MEMORY"
  end

  test "tuple projection lowering skips OOM null checks" do
    out_dir = Path.expand("tmp/tuple_proj_null_check_out", __DIR__)
    project_dir = Path.expand("tmp/tuple_proj_null_check_project", __DIR__)
    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    main =
        let
            ( x, y ) =
                ( 1, 2 )
        in
        x + y
    """)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "elmc_tuple_first("
    assert c =~ "elmc_tuple_second("
    refute Regex.match?(~r/elmc_tuple_first\([^)]+\);\s*if \(!owned\[/, c)
    refute Regex.match?(~r/elmc_tuple_second\([^)]+\);\s*if \(!owned\[/, c)
  end

  test "record field corpus main lowers owned slots and RC callee bridge" do
    out_dir = Path.expand("tmp/record_field_main_lower", __DIR__)
    File.rm_rf!(out_dir)

    tmp = Path.expand("tmp/record_field_test_probe", __DIR__)
    src = Path.join(Elmc.Test.ElmRunCorpus.corpus_dir(), "Basics/RecordFieldTest.elm")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    File.cp!(src, Path.join(tmp, "RecordFieldTest.elm"))

    File.write!(
      Path.join(tmp, "elm.json"),
      Jason.encode!(%{type: "application", "source-directories": ["."], "elm-version": "0.19.1", dependencies: %{direct: %{}, indirect: %{}}}, pretty: true) <> "\n"
    )

    assert {:ok, _result} =
             Elmc.compile(tmp, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "RecordFieldTest",
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "static ElmcValue * elmc_fn_RecordFieldTest_main(void)"
    assert c =~ "ElmcValue *owned["
    assert c =~ "elmc_fn_RecordFieldTest_start(&owned["
    refute c =~ "elmc_fn_RecordFieldTest_start(&owned[0], )"
    assert c =~ ~s/"empty"/
    assert c =~ "elmc_release_array_lifo(owned,"
    refute c =~ ~r/elmc_record_get_index\([^;]+\);\n\s+if \(!owned/
  end

  test "if cfg emits br_if terminator in generated C" do
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

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    refute Regex.match?(~r/elmc_plan_block_\d+:\s*\n\s*elmc_plan_block_\d+:/, c)
    assert c =~ "if (elmc_as_bool("
  end

  test "sequential br targets fall through without redundant goto" do
    out_dir = Path.expand("tmp/plan_br_fallthrough_out", __DIR__)
    project_dir = Path.expand("tmp/plan_br_fallthrough_project", __DIR__)
    template_main = Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(template_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "goto elmc_plan_block_"
    refute Regex.match?(~r/goto elmc_plan_block_(\d+);\s*\n\s*elmc_plan_block_\1:/, c)
    assert c =~ "switch (" or c =~ "else if (elmc_union_tag_matches"
  end

  test "release_array_lifo dedupes aliased owned slots" do
    decl = Elmc.Runtime.RcMacros.release_array_lifo_declaration()
    assert decl =~ "for (size_t i = 0; i < n; i++)"
    assert decl =~ "if (slots[i] == value)"
  end

  test "cmd_batch is value-returning not RC allocator" do
    refute Elmc.Backend.Plan.RuntimeBuiltins.fallible?(:cmd_batch)
    assert Elmc.Backend.Plan.RuntimeBuiltins.value_return?(:cmd_batch)
  end

  test "native Int param boxes into Basics.modBy boxed operands" do
    decl = %{
      name: "dropIndex",
      args: ["pages", "index"],
      type: "List Page -> Int -> Int",
      ownership: [:borrow_arg],
      expr: %{
        op: :call,
        name: "Basics.modBy",
        args: [
          %{op: :call, name: "List.length", args: [%{op: :var, name: "pages"}]},
          %{op: :var, name: "index"}
        ]
      }
    }

    decl_map = %{
      {"Main", "dropIndex"} => %{
        name: "dropIndex",
        args: ["pages", "index"],
        type: "List Page -> Int -> Int",
        ownership: [:borrow_arg]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)

    Process.put(:elmc_program_decls, decl_map)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_basics_mod_by("
    assert c =~ "elmc_small_int(index)" or c =~ "elmc_new_int_take(index)" or
             c =~ "elmc_new_int(&owned[0], index)"
    refute c =~ "(void)index;"
  end

  test "pathFilled render op keeps boxed path payload in tuple2" do
    triangle =
      %{
        op: :call,
        name: "Pebble.Ui.path",
        args: [
          %{op: :list_literal, items: []},
          %{op: :record_literal, fields: [%{name: "x", expr: %{op: :int_literal, value: 0}}]},
          %{op: :record_literal, fields: [%{name: "y", expr: %{op: :int_literal, value: 0}}]},
          %{op: :int_literal, value: 0}
        ]
      }

    decl = %{
      name: "pathCmd",
      args: ["triangle"],
      expr: %{
        op: :call,
        name: "Pebble.Ui.pathFilled",
        args: [%{op: :var, name: "triangle"}]
      }
    }

    decl_map = %{
      {"Main", "pathCmd"} => %{name: "pathCmd", args: ["triangle"], ownership: [:borrow_arg]}
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(
               Map.put(decl, :expr, %{
                 op: :call,
                 name: "Pebble.Ui.pathFilled",
                 args: [triangle]
               }),
               "Main",
               decl_map,
               rc_required: true
             )

    Process.put(:elmc_program_decls, decl_map)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_tuple2("
    refute c =~ "elmc_tuple2_ints(&"
    assert c =~ "plan_ephemeral_box_"
    assert c =~ "elmc_release(plan_ephemeral_box_"
  end

  test "record_get args make kernel log cmds pebble_cmd eligible" do
    arg = %{
      op: :record_get,
      base: %{op: :var, name: "model"},
      field: "code",
      field_index: 0
    }

    assert %{op: :pebble_cmd} =
             Elmc.Backend.CCodegen.SpecialValues.special_value_from_target(
               "Elm.Kernel.PebbleWatch.logInfoCode",
               [arg]
             )
  end

  test "result Ok lowering reads fn_out when wrapping prior tail value" do
    out_dir = Path.expand("tmp/rc_track_result_ok_four_lower", __DIR__)
    File.rm_rf!(out_dir)

    tmp = Path.expand("tmp/rc_track_result_ok_four_probe", __DIR__)
    src = Path.expand("fixtures/rc_track_result_project/src/RcTrackResultProbe.elm", __DIR__)
    File.rm_rf!(tmp)
    File.mkdir_p!(Path.join(tmp, "src"))
    File.cp!(src, Path.join(tmp, "src/RcTrackResultProbe.elm"))

    File.write!(
      Path.join(tmp, "elm.json"),
      Jason.encode!(
        %{
          "type" => "application",
          "source-directories" => ["src"],
          "elm-version" => "0.19.1",
          "dependencies" => %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}}
        },
        pretty: true
      ) <> "\n"
    )

    assert {:ok, _} =
             Elmc.compile(tmp, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "RcTrackResultProbe",
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "elmc_result_ok_own(out, *out)"
  end
end
