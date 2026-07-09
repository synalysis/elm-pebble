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
    assert c =~ "CHECK_RC(Rc)"
    assert c =~ "CATCH_BEGIN"
    assert c =~ "return Rc;"
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
    assert c =~ "elmc_record_new_values_ints"
    refute c =~ "elmc_record_new(&owned"
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
    assert c =~ "elmc_retain(owned[0])"
    assert c =~ "elmc_record_update_index_cow_drop("
    refute c =~ "Rc = elmc_record_update_index_cow_drop("
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
    assert c =~ "elmc_record_get_index(owned[0], 1 /* score */)"
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
    assert c =~ "elmc_new_string_take(\"empty\")"
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
    assert c =~ "else if (elmc_union_tag_matches"
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
end
