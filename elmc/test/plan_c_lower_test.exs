defmodule Elmc.PlanCLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.CachedCompile
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

  test "record_new retains when the same owned slot appears twice in values" do
    decl = %{
      name: "dupField",
      args: ["x"],
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "a", expr: %{op: :var, name: "x"}},
          %{name: "b", expr: %{op: :var, name: "x"}}
        ]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_record_new_values_take"
    assert c =~ ~r/elmc_retain\((owned\[\d+\]|x)\)/
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
    assert c =~ "Rc = elmc_record_update_index_int_cow(out, model,"
    refute c =~ "elmc_record_update_index_int_cow_drop"
    refute c =~ "elmc_record_update_index_cow_drop("
    assert c =~ "*out == model"
    assert c =~ "*out = elmc_retain(*out)"
    refute c =~ ~r/elmc_release\(owned\[\d+\]\)/
  end

  test "maybe_with_default_int into Int record field stays native" do
    Process.put(:elmc_record_field_types, %{"Model" => %{"best" => "Int"}})

    on_exit(fn -> Process.delete(:elmc_record_field_types) end)

    decl = %{
      name: "loadBest",
      args: ["model", "parsed"],
      type: "Model -> Maybe Int -> Model",
      ownership: [:borrow_arg, :retain_result],
      expr: %{
        op: :record_update,
        base: %{op: :var, name: "model"},
        fields: [
          %{
            field: "best",
            expr: %{
              op: :qualified_call,
              target: "Maybe.withDefault",
              args: [
                %{op: :int_literal, value: 0},
                %{op: :var, name: "parsed"}
              ]
            }
          }
        ]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_maybe_with_default_int(0"
    assert c =~ "elmc_record_update_index_int_cow(out, model,"
    refute c =~ "elmc_record_update_index_int_cow_drop"
    refute c =~ ~r/elmc_new_int\(&owned\[\d+\], elmc_maybe_with_default_int/
    refute c =~ "elmc_record_update_index_cow_drop("
  end

  test "inlined native const ints do not emit invalid C bindings" do
    # Const ints that are only used as operands are mapped into native_int_regs as
    # the literal text for use-site inlining. Emitting `const elmc_int_t 2 = 2;` is
    # not valid C and must be skipped; use sites already see the literal.
    decl = %{
      name: "scaleByTwo",
      args: ["n"],
      expr: %{
        op: :call,
        name: "__mul__",
        args: [%{op: :var, name: "n"}, %{op: :int_literal, value: 2}]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    refute c =~ ~r/const elmc_int_t \d+\s*=/
    refute c =~ ~r/const elmc_int_t ELMC_[A-Z0-9_]+\s*=/
  end

  test "native int merge stores into plan_native_int locals" do
    # Constructor-tag / int switch arms writing a shared native merge (pieceColor-like).
    decl = %{
      name: "pieceColor",
      args: ["index"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "index"},
        branches: [
          %{
            pattern: %{kind: :int, value: 0},
            expr: %{op: :c_int_expr, value: "ELMC_COLOR_RED"}
          },
          %{
            pattern: %{kind: :int, value: 1},
            expr: %{op: :c_int_expr, value: "ELMC_COLOR_BLUE"}
          },
          %{
            pattern: %{kind: :wildcard},
            expr: %{op: :c_int_expr, value: "ELMC_COLOR_BLACK"}
          }
        ]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    refute c =~ ~r/const elmc_int_t ELMC_COLOR_/
    refute c =~ ~r/const elmc_int_t \d+\s*=/
    assert c =~ "ELMC_COLOR_RED"
    assert c =~ "ELMC_COLOR_BLUE"
    assert c =~ "ELMC_COLOR_BLACK"
    assert c =~ "elmc_new_int(&owned[0], ELMC_COLOR_RED)"
    assert c =~ "elmc_new_int(&owned[0], ELMC_COLOR_BLUE)"
  end

  test "RC emit never mid-body releases owned slots after retain-style consumes" do
    # Boxed values (not native-int fused) land in owned[]; RC `tuple2` retains them
    # while the plan marks consumes. Emit must leave pointers for frame LIFO.
    decl = %{
      name: "pair",
      args: [],
      expr: %{
        op: :tuple2,
        left: %{
          op: :constructor_call,
          target: "Maybe.Just",
          args: [%{op: :int_literal, value: 1}]
        },
        right: %{
          op: :constructor_call,
          target: "Maybe.Just",
          args: [%{op: :int_literal, value: 2}]
        }
      }
    }

    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", %{}, rc_required: true)

    c = CLowerFunction.emit(plan)
    assert c =~ "ElmcValue *owned["
    assert c =~ "elmc_tuple2("
    assert c =~ "elmc_release_array_lifo(owned,"
    refute c =~ ~r/elmc_release\(owned\[\d+\]\)/

    # Branch merge into a retain-style consume must follow the same rule.
    branched = %{
      name: "pickPair",
      args: ["flag"],
      expr: %{
        op: :tuple2,
        left: %{
          op: :if,
          cond: %{op: :var, name: "flag"},
          then_expr: %{
            op: :constructor_call,
            target: "Maybe.Just",
            args: [%{op: :int_literal, value: 1}]
          },
          else_expr: %{
            op: :constructor_call,
            target: "Maybe.Just",
            args: [%{op: :int_literal, value: 2}]
          }
        },
        right: %{
          op: :constructor_call,
          target: "Maybe.Nothing",
          args: []
        }
      }
    }

    assert {:ok, branched_plan} =
             Elmc.Backend.Plan.Lower.Function.lower(branched, "Main", %{}, rc_required: true)

    branched_c = CLowerFunction.emit(branched_plan)
    assert branched_c =~ "ElmcValue *owned["
    assert branched_c =~ "elmc_tuple2("
    assert branched_c =~ "elmc_release_array_lifo(owned,"
    refute branched_c =~ ~r/elmc_release\(owned\[\d+\]\)/
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

  test "local (Int,Int) destructure unboxes without heap tuple or OOM null checks" do
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
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    # Local (Int,Int) is scalar-replaced: no heap pair and no tuple_proj peels.
    refute c =~ "elmc_tuple2_ints"
    refute c =~ "elmc_tuple_first"
    refute c =~ "elmc_tuple_second"
    assert c =~ "1 + 2"
  end

  test "escaping tuple param projections skip OOM null checks" do
    out_dir = Path.expand("tmp/tuple_param_proj_oom_out", __DIR__)
    project_dir = Path.expand("tmp/tuple_param_proj_oom_project", __DIR__)
    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    sumPair : ( Int, Int ) -> Int
    sumPair ( x, y ) =
        x + y

    main =
        sumPair ( 1, 2 )
    """)

    assert {:ok, _} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "elmc_tuple_first" or c =~ "elmc_tuple_second"
    refute Regex.match?(~r/elmc_tuple_first\([^)]+\);\s*if \(!owned\[/, c)
    refute Regex.match?(~r/elmc_tuple_second\([^)]+\);\s*if \(!owned\[/, c)
  end

  test "view_peel retain and list_head use correct OOM contracts" do
    out_dir = Path.expand("tmp/view_peel_oom_out", __DIR__)
    project_dir = Path.expand("tmp/view_peel_oom_project", __DIR__)
    File.rm_rf!(out_dir)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    unwrap : Maybe Int -> Int
    unwrap m =
        case m of
            Just n ->
                n

            Nothing ->
                0

    firstOrZero : List a -> Int
    firstOrZero xs =
        case List.head xs of
            Just _ ->
                1

            Nothing ->
                0

    main =
        unwrap (Just 1) + firstOrZero [ "a", "b" ]
    """)

    assert {:ok, _} =
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true,
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    # Borrowed Maybe peels stay borrows (no retain) so later record COW can
    # mutate in place. Publish retains the result; peels never allocate.
    assert c =~ "elmc_maybe_just_payload("
    assert c =~ ~r/\*out = elmc_retain\(owned\[\d+\]\)/
    refute c =~ "elmc_retain(elmc_maybe_just_payload("
    refute Regex.match?(
             ~r/elmc_maybe_just_payload\([^)]+\);\s*if \(!owned\[/,
             c
           )

    # Allocating List.head must use RC out-param, not a null-as-OOM value return.
    assert c =~ ~r/Rc = elmc_list_head\(&owned\[\d+\],/
    refute Regex.match?(~r/owned\[\d+\] = elmc_list_head\([^;]+\);\s*if \(!owned\[/, c)
  end

  test "record field corpus main lowers owned slots and RC callee bridge" do
    out_dir = Path.expand("tmp/record_field_main_lower", __DIR__)
    File.rm_rf!(out_dir)

    # Vendored from elm-run RecordFieldTest — do not require optional corpus submodule.
    project_dir = Path.expand("fixtures/record_field_test_project", __DIR__)

    assert {:ok, _result} =
             CachedCompile.compile(project_dir, %{
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

  @tag timeout: 300_000
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
             CachedCompile.compile(project_dir, %{
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

  test "release_array_lifo releases each owned slot independently" do
    decl = Elmc.Runtime.RcMacros.release_array_lifo_declaration()
    assert decl =~ "slots[count] = NULL"
    assert decl =~ "elmc_release(value)"
    refute decl =~ "for (size_t i = 0; i < n; i++)"
    assert decl =~ "elmc_owned_null_aliases"
  end

  test "cmd_batch is fallible RC allocator" do
    assert Elmc.Backend.Plan.RuntimeBuiltins.fallible?(:cmd_batch)
    refute Elmc.Backend.Plan.RuntimeBuiltins.value_return?(:cmd_batch)
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
    assert c =~ "elmc_small_int(index)" or c =~ "elmc_harness_new_int(index)" or
             c =~ ~r/elmc_new_int\(&owned\[\d+\], index\)/
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
             Elmc.Backend.Plan.Lower.SpecialValues.special_value_from_target(
               "Elm.Kernel.PebbleWatch.logInfoCode",
               [arg]
             )
  end

  @tag timeout: 300_000
  test "result Ok lowering reads fn_out when wrapping prior tail value" do
    out_dir = Path.expand("tmp/rc_track_result_ok_four_lower", __DIR__)
    File.rm_rf!(out_dir)

    tmp = Path.expand("tmp/rc_track_result_ok_four_probe", __DIR__)
    src = Path.expand("fixtures/rc_track_result_project/src/RcTrackResultProbe.elm", __DIR__)

    Elmc.TestSupport.ElmJson.write_probe_project!(
      tmp,
      File.read!(src),
      rel_path: "RcTrackResultProbe.elm"
    )

    assert {:ok, _} =
             CachedCompile.compile(tmp, %{
               out_dir: out_dir,
               strip_dead_code: false,
               entry_module: "RcTrackResultProbe",
               plan_ir_mode: :primary
             })

    c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert c =~ "elmc_result_ok_own(out, *out)"
  end

  test "result_and_then nulls consumed let-bound result without double release" do
    decl = %{
      name: "bind",
      args: ["result"],
      expr: %{
        op: :qualified_call,
        target: "Result.andThen",
        args: [
          %{op: :lambda, args: ["s"], body: %{op: :var, name: "s"}},
          %{op: :var, name: "result"}
        ]
      }
    }

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(
               decl,
               "Main",
               %{{"Main", "bind"} => decl},
               rc_required: true
             )

    c = Elmc.Backend.C.Lower.Function.emit(plan)
    assert c =~ "elmc_result_and_then("
    assert c =~ "owned[1] = NULL;"
    refute c =~ ~r/elmc_result_and_then\([^)]+\);\s*CHECK_RC\(Rc\);\s*elmc_release\(owned\[1\]\)/
  end

  test "Int identity peels boxed param into native return without tmp retain" do
    decl = %{
      name: "identityInt",
      args: ["x"],
      type: "Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{op: :var, name: "x"}
    }

    decl_map = %{{"Main", "identityInt"} => decl}
    Process.put(:elmc_program_decls, decl_map)

    assert {:ok, plan} =
             Elmc.Backend.Plan.Lower.Function.lower(decl, "Main", decl_map, rc_required: true)

    c = CLowerFunction.emit(plan)
    refute c =~ "tmp_"
    refute c =~ "elmc_retain"
    assert c =~ "elmc_as_int(x)"
    assert c =~ "return "
  end
end
