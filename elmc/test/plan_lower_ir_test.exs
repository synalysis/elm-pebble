defmodule Elmc.PlanLowerIrTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.{Lower, Program, Runtime}
  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.{Debug, Lower.Function, Verify}

  test "lowers nested int case without stealing sibling arm block ids" do
    decl = %{
      name: "nested",
      args: ["x", "y"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "x"},
        branches: [
          %{
            pattern: %{kind: :int, value: 0},
            expr: %{
              op: :case,
              subject: %{op: :var, name: "y"},
              branches: [
                %{pattern: %{kind: :int, value: 0}, expr: %{op: :int_literal, value: 100}},
                %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 101}},
                %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 102}}
              ]
            }
          },
          %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 200}},
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    assert :ok = Verify.run(plan)

    refute Enum.any?(plan.blocks, fn block ->
             match?({:br, id} when id == block.id, block.terminator)
           end)

    section = Lower.lower(plan)

    assert {:ok, 100} = Runtime.run_section(section, params: [0, 0], plan_key: {"Main", "nested"})
    assert {:ok, 101} = Runtime.run_section(section, params: [0, 1], plan_key: {"Main", "nested"})
    assert {:ok, 200} = Runtime.run_section(section, params: [1, 0], plan_key: {"Main", "nested"})
    assert {:ok, 0} = Runtime.run_section(section, params: [2, 0], plan_key: {"Main", "nested"})
  end

  test "record_get uses record alias shape indices" do
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

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    [record_get] =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))

    assert record_get.args[:field_index] =~ "1"
    assert :ok = Verify.run(plan)
  end

  test "record_new orders literal fields by alias shape" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Main", "Model"} => ["board", "score", "lines"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    decl = %{
      name: "scores",
      args: [],
      expr: %{
        op: :record_literal,
        fields: [
          %{name: "lines", expr: %{op: :int_literal, value: 3}},
          %{name: "board", expr: %{op: :int_literal, value: 1}},
          %{name: "score", expr: %{op: :int_literal, value: 2}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)

    section = Lower.lower(plan)

    assert {:ok, {:record, [1, 2, 3]}} =
             Runtime.run_section(section, plan_key: {"Main", "scores"})

    assert :ok = Verify.run(plan)
  end

  test "if cfg skips untaken branch side effects" do
    decl_map = %{
      {"Main", "ok"} => %{
        name: "ok",
        args: [],
        expr: %{op: :int_literal, value: 1}
      },
      {"Main", "bomb"} => %{
        name: "bomb",
        args: ["x"],
        expr: %{
          op: :runtime_call,
          function: "elmc_list_map",
          args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 0}]
        }
      },
      {"Main", "gate"} => %{
        name: "gate",
        args: ["pick"],
        expr: %{
          op: :if,
          cond: %{
            op: :compare,
            kind: :eq,
            left: %{op: :var, name: "pick"},
            right: %{op: :int_literal, value: 0}
          },
          then_expr: %{op: :qualified_call, target: "Main.ok", args: []},
          else_expr: %{
            op: :qualified_call,
            target: "Main.bomb",
            args: [%{op: :int_literal, value: 0}]
          }
        }
      }
    }

    assert {:ok, plan} = Function.lower(Map.fetch!(decl_map, {"Main", "gate"}), "Main", decl_map, rc_required: false)
    assert :ok = Verify.run(plan)

    assert {:ok, program} = Program.link(decl_map, {"Main", "gate"})
    assert {:ok, 1} = Program.run(program, params: [0])
  end

  test "maybe case cfg skips untaken arm side effects" do
    decl_map = %{
      {"Main", "ok"} => %{
        name: "ok",
        args: [],
        expr: %{op: :int_literal, value: 1}
      },
      {"Main", "bomb"} => %{
        name: "bomb",
        args: ["x"],
        expr: %{
          op: :runtime_call,
          function: "elmc_list_map",
          args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 0}]
        }
      },
      {"Main", "gate"} => %{
        name: "gate",
        args: ["maybe"],
        expr: %{
          op: :case,
          subject: %{op: :var, name: "maybe"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Nothing"},
              expr: %{op: :qualified_call, target: "Main.ok", args: []}
            },
            %{
              pattern: %{kind: :var, name: "payload"},
              expr: %{
                op: :qualified_call,
                target: "Main.bomb",
                args: [%{op: :int_literal, value: 0}]
              }
            }
          ]
        }
      }
    }

    assert {:ok, plan} = Function.lower(Map.fetch!(decl_map, {"Main", "gate"}), "Main", decl_map, rc_required: false)
    assert length(plan.blocks) >= 4
    assert :ok = Verify.run(plan)

    assert {:ok, program} = Program.link(decl_map, {"Main", "gate"})
    assert {:ok, 1} = Program.run(program, params: [nil])
  end

  test "lowers nested maybe case — callee scratch reg, not fn_out" do
    decl = %{
      name: "pick",
      args: ["from", "to"],
      expr: %{
        op: :case,
        subject: %{
          op: :qualified_call,
          target: "Main.lookupVector",
          args: [
            %{op: :var, name: "from"},
            %{op: :var, name: "to"}
          ]
        },
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing"},
            expr: %{op: :cmd_none}
          },
          %{
            pattern: %{kind: :var, name: "vec"},
            expr: %{op: :var, name: "vec"}
          }
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)

    dump = Debug.dump(plan)
    assert dump =~ "call_fn"
    assert dump =~ "lookupVector"
    assert dump =~ "test_maybe_nothing"
    refute dump =~ "dest: :fn_out"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_fn_Main_lookupVector"
    refute c =~ "elmc_fn_Main_lookupVector(out"
    assert c =~ "elmc_maybe_is_nothing"
    assert c =~ "elmc_retain"
  end

  test "lowers record update and compare for if guard" do
    decl = %{
      name: "bump",
      args: ["model", "n"],
      expr: %{
        op: :if,
        cond: %{
          op: :compare,
          kind: :eq,
          left: %{op: :var, name: "n"},
          right: %{op: :int_literal, value: 0}
        },
        then_expr: %{op: :var, name: "model"},
        else_expr: %{
          op: :record_update,
          base: %{op: :var, name: "model"},
          fields: [%{field: "count", expr: %{op: :var, name: "n"}}]
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_as_int"
    # Borrowed `model` param must use cow (not cow_drop) so a copy path does
    # not release the caller's record; retain only when dest aliases the base.
    assert c =~ "elmc_record_update_index_cow("
    refute c =~ "elmc_record_update_index_cow_drop("
    assert c =~ "elmc_retain"
  end

  test "lowers Maybe var against constructor_ref Nothing with test_maybe_nothing" do
    decl = %{
      name: "hasValue",
      args: ["maybe"],
      expr: %{
        op: :compare,
        kind: :neq,
        left: %{op: :var, name: "maybe"},
        right: %{op: :constructor_ref, target: "Nothing"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    dump = Debug.dump(plan)
    assert dump =~ "test_maybe_nothing"
    refute dump =~ "elmc_as_int(maybe)"
  end

  test "lowers union ctor equality against constructor_ref with test_ctor_tag" do
    Process.put(:elmc_constructor_tags, %{"StaticBitmap" => 3, "Main.Page.StaticBitmap" => 3})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "onBitmapPage",
      args: ["page"],
      expr: %{
        op: :compare,
        kind: :eq,
        left: %{op: :var, name: "page"},
        right: %{op: :constructor_ref, target: "StaticBitmap"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    dump = Debug.dump(plan)
    assert dump =~ "test_ctor_tag"
    refute dump =~ "elmc_as_int(page)"
  end

  test "lowers Maybe.Just constructor with maybe_just_own" do
    decl = %{
      name: "wrap",
      args: ["x"],
      expr: %{
        op: :constructor_call,
        target: "Maybe.Just",
        args: [%{op: :var, name: "x"}]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "maybe_just_own"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_maybe_just_own"
  end

  test "maybe_just_own passes retain copy when payload is still used later" do
    decl = %{
      name: "pairJustWithPayload",
      args: ["payload"],
      expr: %{
        op: :tuple2,
        left: %{
          op: :constructor_call,
          target: "Maybe.Just",
          args: [%{op: :var, name: "payload"}]
        },
        right: %{op: :var, name: "payload"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)

    assert [_full, _dest_slot, arg_slot] =
             Regex.run(~r/Rc = elmc_maybe_just_own\(&owned\[(\d+)\], owned\[(\d+)\]\)/, c)

    retain_slots =
      Regex.scan(~r/owned\[(\d+)\] = elmc_retain\(payload\)/, c)
      |> Enum.map(fn [_, slot] -> String.to_integer(slot) end)

    assert retain_slots != []
    assert String.to_integer(arg_slot) in retain_slots,
           "expected maybe_just_own to take ownership via retain copy, not alias payload:\n#{c}"

    refute c =~
             ~r/elmc_maybe_just_own\(&owned\[\d+\], owned\[#{arg_slot}\]\);\s*\n\s*CHECK_RC\(Rc\);\s*\n\s*elmc_release\(owned\[#{arg_slot}\]\)/,
           "maybe_just_own transfer must null consumed slot without releasing payload"
  end

  test "lowers Maybe value compared to Nothing with maybe_is_nothing" do
    decl = %{
      name: "hasValue",
      args: ["maybe"],
      expr: %{
        op: :compare,
        kind: :neq,
        left: %{op: :var, name: "maybe"},
        right: %{op: :constructor_call, target: "Maybe.Nothing", args: []}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_maybe_is_nothing"
    refute c =~ "elmc_as_int(maybe) == elmc_as_int"
  end

  test "saturated binary __eq__ lowers to compare, not Module.__eq__ call_fn" do
    decl = %{
      name: "sameName",
      args: ["left", "right"],
      expr: %{
        op: :call,
        name: "__eq__",
        args: [%{op: :var, name: "left"}, %{op: :var, name: "right"}]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Route.Packages.Author_.Name_.Version_.ModuleName_", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    ops = for b <- plan.blocks, i <- b.instrs, do: i.op
    assert :compare in ops
    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, fn
               %{op: :call_fn, args: %{name: "__eq__"}} -> true
               _ -> false
             end)
           end)
  end

  test "deduplicates param load_param per name" do
    decl = %{
      name: "addTwice",
      args: ["x"],
      expr: %{
        op: :compare,
        kind: :eq,
        left: %{op: :var, name: "x"},
        right: %{op: :var, name: "x"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert Regex.scan(~r/load_param/, dump) |> length() == 1
    assert :ok = Verify.run(plan)
  end

  test "lowers tagged constructor case with per-arm merge publish" do
    Process.put(:elmc_constructor_tags, %{"A" => 1, "B" => 2})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "pick",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "A", tag: 1, arg_pattern: nil},
            expr: %{op: :int_literal, value: 10}
          },
          %{
            pattern: %{kind: :constructor, name: "B", tag: 2, arg_pattern: nil},
            expr: %{op: :int_literal, value: 20}
          },
          %{
            pattern: %{kind: :wildcard},
            expr: %{op: :int_literal, value: 0}
          }
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    refute dump =~ "switch_ctor_tag"
    assert length(plan.blocks) >= 4
    assert dump =~ "terminator switch_tag"
    assert dump =~ "terminator br"
    # Merge publish may retain arm const_int temps into the merge reg.
    assert dump =~ "publish → fn_out"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_union_tag_matches"
    assert c =~ "goto elmc_plan_block_"
    assert c =~ "*out = owned[0];" or c =~ ~r/\*out = owned\[\d+\];/
    # Merge may retain arm temps into the publish slot before nulling sources.
    refute c =~ ~r/owned\[\d+\] = owned\[\d+\];/
  end

  test "lowers int add_const for record/cmd tuple sharing" do
    decl = %{
      name: "bump",
      args: ["n"],
      expr: %{
        op: :let_in,
        name: "next",
        value_expr: %{op: :add_const, var: "n", value: 1},
        in_expr: %{
          op: :tuple2,
          left: %{
            op: :record_literal,
            fields: [%{name: "value", expr: %{op: :var, name: "next"}}]
          },
          right: %{op: :var, name: "next"}
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "int_arith"
    assert dump =~ "retain"
    assert :ok = Verify.run(plan)
  end

  test "record update field __add__ lowers to int_arith not call_fn" do
    decl = %{
      name: "bumpY",
      args: ["m", "piece"],
      expr: %{
        op: :record_update,
        base: %{op: :var, name: "piece"},
        fields: [
          %{
            field: "y",
            expr: %{
              op: :call,
              name: "__add__",
              args: [
                %{op: :field_access, arg: %{op: :var, name: "piece"}, field: "y"},
                %{op: :int_literal, value: 1}
              ]
            }
          }
        ]
      }
    }

    shapes = %{{"Main", "ActivePiece"} => ["kind", "rot", "x", "y"]}
    Process.put(:elmc_record_alias_shapes, shapes)

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    dump = Debug.dump(plan)
    assert dump =~ "int_arith"
    refute dump =~ "call_fn"
    assert :ok = Verify.run(plan)
  end

  test "__append__ lowers to list_append runtime builtin" do
    decl = %{
      name: "join",
      args: ["left", "right"],
      expr: %{
        op: :call,
        name: "__append__",
        args: [%{op: :var, name: "left"}, %{op: :var, name: "right"}]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    dump = Debug.dump(plan)
    assert dump =~ "list_append"
    refute dump =~ "__append__"
    assert :ok = Verify.run(plan)

    section = Lower.lower(plan)

    assert {:ok, [1, 2, 3, 4]} =
             Runtime.run_section(section, params: [[1, 2], [3, 4]], plan_key: {"Main", "join"})
  end

  test "__idiv__ with add_const lowers to int_arith not call_fn" do
    decl = %{
      name: "half",
      args: ["c10"],
      expr: %{
        op: :call,
        name: "__idiv__",
        args: [
          %{op: :add_const, var: "c10", value: 5},
          %{op: :int_literal, value: 10}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "idiv_vars"
    refute dump =~ "__idiv__"
    assert :ok = Verify.run(plan)
  end

  test "string __append__ lowers to string_append runtime builtin" do
    decl = %{
      name: "label",
      args: ["n"],
      expr: %{
        op: :call,
        name: "__append__",
        args: [
          %{op: :qualified_call, target: "String.fromInt", args: [%{op: :var, name: "n"}]},
          %{op: :string_literal, value: "C"}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "string_append"
    refute dump =~ "list_append"
    assert :ok = Verify.run(plan)
  end

  test "String-typed params use string_append for ++ (not List.append)" do
    decl = %{
      name: "joinLines",
      args: ["sep", "x", "rest"],
      type: "String -> String -> String -> String",
      expr: %{
        op: :call,
        name: "__append__",
        args: [
          %{op: :var, name: "x"},
          %{
            op: :call,
            name: "__append__",
            args: [%{op: :var, name: "sep"}, %{op: :var, name: "rest"}]
          }
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "JoinTest", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "string_append"
    refute dump =~ "list_append"
    assert :ok = Verify.run(plan)
  end

  test "nested maybe constructor case seals tag-switch merge block" do
    decl = %{
      name: "readingString",
      args: ["model"],
      expr: %{
        op: :case,
        subject: %{op: :field_access, arg: %{op: :var, name: "model"}, field: "reading"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Nothing", tag: 0},
            expr: %{op: :string_literal, value: "--"}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "Just",
              tag: 1,
              arg_pattern: %{kind: :constructor, name: "Celsius", tag: 1, bind: "c10"}
            },
            expr: %{
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
                      args: [
                        %{op: :add_const, var: "c10", value: 5},
                        %{op: :int_literal, value: 10}
                      ]
                    }
                  ]
                },
                %{op: :string_literal, value: "C"}
              ]
            }
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "Just",
              tag: 1,
              arg_pattern: %{kind: :constructor, name: "Fahrenheit", tag: 2, bind: "f10"}
            },
            expr: %{op: :string_literal, value: "hot"}
          }
        ]
      }
    }

    Process.put(:elmc_constructor_tags, %{
      "Nothing" => 0,
      "Just" => 1,
      "Celsius" => 1,
      "Fahrenheit" => 2
    })

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    block_ids = MapSet.new(Enum.map(plan.blocks, & &1.id))

    # Arms jump to a shared merge; consuming retains coalesce into producers that
    # write the merge register directly (no retain juggling required).
    # view_peel retains (Maybe Just payload) are still required and must remain.
    assert Enum.any?(plan.blocks, fn block -> match?({:br, _}, block.terminator) end)

    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, fn
               %{op: :call_runtime, args: %{builtin: :retain} = args, effects: effects} ->
                 not Map.has_key?(args, :view_peel) and
                   match?([_ | _], List.wrap(Map.get(effects, :consumes, [])))

               _ ->
                 false
             end)
           end)

    refute dangling_branch_target?(plan.blocks, block_ids)
    assert :ok = Verify.run(plan)
  end

  defp dangling_branch_target?(blocks, block_ids) do
    Enum.any?(blocks, fn block ->
      case block.terminator do
        {:br, target} -> not MapSet.member?(block_ids, target)
        {:br_if, then_id, else_id, _} ->
          not MapSet.member?(block_ids, then_id) or not MapSet.member?(block_ids, else_id)

        {:switch_tag, _, arms, default} ->
          arm_ids_invalid? =
            Enum.any?(arms, fn
              {_, id} -> not MapSet.member?(block_ids, id)
              {_, id, _} -> not MapSet.member?(block_ids, id)
              _ -> true
            end)

          arm_ids_invalid? or not MapSet.member?(block_ids, default)

        _ ->
          false
      end
    end)
  end

  test "guarded Msg case with param loads branches from entry into tag tests" do
    # Reproduces Tangram Main.update: GuardedSwitch sealed the entry (param loads)
    # with :none → C `__plan_state = -1` on case 0, so CurrentDateTime never ran
    # and timeText stayed "--:--".
    decl = %{
      name: "update",
      args: ["msg", "model"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "GotTime",
              tag: 1,
              arg_pattern: %{kind: :var, name: "t"}
            },
            expr: %{op: :var, name: "t"}
          },
          %{
            pattern: %{kind: :constructor, name: "Tick", tag: 2, arg_pattern: nil},
            expr: %{op: :var, name: "model"}
          }
        ]
      }
    }

    Process.put(:elmc_constructor_tags, %{"GotTime" => 1, "Tick" => 2})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    entry = Enum.find(plan.blocks, &(&1.id == plan.entry_block))
    refute match?(:none, entry.terminator), "entry must not halt before Msg tag tests"

    assert match?({:br, _}, entry.terminator) or
             match?({:switch_tag, _, _, _}, entry.terminator),
           "entry must branch into tag tests, got #{inspect(entry.terminator)}"

    c = CLowerFunction.emit(plan)
    refute Regex.match?(
             ~r/case 0:\s*__plan_state = -1; break;\s*case 1:/s,
             c
           ),
           "entry case must fall through to tag-match chain, not halt"

    assert c =~ "elmc_union_tag_matches"
  end

  test "Just-Just tuple case peels without heap tuple2 or plan_state" do
    decl = %{
      name: "bothJust",
      args: ["maybeRise", "maybeSet"],
      expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "maybeRise"},
          right: %{op: :var, name: "maybeSet"}
        },
        in_expr: %{
          op: :case,
          subject: "caseSubject",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :constructor, name: "Just", bind: "rise", arg_pattern: nil},
                  %{kind: :constructor, name: "Just", bind: "set", arg_pattern: nil}
                ]
              },
              expr: %{op: :var, name: "rise"}
            },
            %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
          ]
        }
      }
    }

    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2("
    refute c =~ "__plan_state"
    assert c =~ "elmc_maybe_is_nothing"
  end

  test "mixed Just/Nothing 2-tuple case peels without heap tuple2" do
    decl = %{
      name: "justNothing",
      args: ["maybeRise", "maybeSet"],
      expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "maybeRise"},
          right: %{op: :var, name: "maybeSet"}
        },
        in_expr: %{
          op: :case,
          subject: "caseSubject",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :constructor, name: "Just", bind: "rise", arg_pattern: nil},
                  %{kind: :constructor, name: "Nothing"}
                ]
              },
              expr: %{op: :var, name: "rise"}
            },
            %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
          ]
        }
      }
    }

    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2("
    refute c =~ "__plan_state"
    assert c =~ "elmc_maybe_is_nothing"
  end

  test "mixed Just/Nothing 3-tuple case peels without heap tuple2" do
    decl = %{
      name: "justNothingJust",
      args: ["maybeA", "maybeB", "maybeC"],
      expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "maybeA"},
          right: %{
            op: :tuple2,
            left: %{op: :var, name: "maybeB"},
            right: %{op: :var, name: "maybeC"}
          }
        },
        in_expr: %{
          op: :case,
          subject: "caseSubject",
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :constructor, name: "Just", bind: "a", arg_pattern: nil},
                  %{kind: :constructor, name: "Nothing"},
                  %{kind: :constructor, name: "Just", bind: "c", arg_pattern: nil}
                ]
              },
              expr: %{op: :var, name: "a"}
            },
            %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
          ]
        }
      }
    }

    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    c = CLowerFunction.emit(plan)
    refute c =~ "elmc_tuple2("
    refute c =~ "__plan_state"
    assert c =~ "elmc_maybe_is_nothing"
  end

  test "record pattern plus wildcard lowers through GuardedSwitch" do
    decl = %{
      name: "showRec",
      args: ["rec"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "rec"},
        branches: [
          %{
            pattern: %{kind: :record, fields: ["n", "label"]},
            expr: %{op: :var, name: "n"}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)
    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_record_get"
    refute c =~ "__plan_state = -1"
  end

  test "multi-ctor case with var and tuple payloads lowers to switch_tag" do
    # Companion-style arms bind payloads via arg_pattern vars/tuples. TagSwitch
    # must accept those or GuardedSwitch emits huge sequential plan-state chains.
    decl = %{
      name: "fromPhone",
      args: ["message"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "message"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "ProvideTimezone",
              tag: 1,
              arg_pattern: %{kind: :var, name: "offset"}
            },
            expr: %{op: :var, name: "offset"}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "ProvideSun",
              tag: 2,
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "rise"},
                  %{kind: :var, name: "set"},
                  %{kind: :var, name: "mode"}
                ]
              }
            },
            expr: %{op: :var, name: "rise"}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    Process.put(:elmc_constructor_tags, %{"ProvideTimezone" => 1, "ProvideSun" => 2})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert Enum.any?(plan.blocks, fn block -> match?({:switch_tag, _, _, _}, block.terminator) end)

    c = CLowerFunction.emit(plan)
    # switch_tag emits if/goto tag matches — not a __plan_state interpreter.
    assert c =~ "elmc_union_tag_matches"
    refute c =~ "__plan_state"
  end

  test "Result Ok Err case lowers to switch_tag not sequential arms" do
    decl = %{
      name: "pick",
      args: ["r"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "r"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Ok", tag: 0, bind: "v"},
            expr: %{op: :int_literal, value: 11}
          },
          %{
            pattern: %{kind: :constructor, name: "Err", tag: 1, bind: "_"},
            expr: %{op: :int_literal, value: 22}
          }
        ]
      }
    }

    Process.put(:elmc_constructor_tags, %{"Ok" => 0, "Err" => 1})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    assert Enum.any?(plan.blocks, fn block -> match?({:switch_tag, _, _, _}, block.terminator) end)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_union_tag_matches"

    case {:binary.match(c, ", 11)"), :binary.match(c, ", 22)")} do
      {{ok_pos, _}, {err_pos, _}} when ok_pos < err_pos ->
        between = String.slice(c, ok_pos, err_pos - ok_pos)
        assert between =~ "goto elmc_plan_block"

      _ ->
        :ok
    end
  end

  test "tag_switch merge block branches to ret for state_switch emit" do
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
            pattern: %{kind: :wildcard},
            expr: %{op: :tuple2, left: %{op: :var, name: "model"}, right: %{op: :int_literal, value: 0}}
          }
        ]
      }
    }

    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_emit: :state_switch})

    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    refute Enum.any?(plan.blocks, &match?(%{terminator: :none}, &1))

    blocks_by_id = Map.new(plan.blocks, &{&1.id, &1})

    br_to_ret? =
      Enum.any?(plan.blocks, fn
        %{terminator: {:br, target}} ->
          match?(%{terminator: {:ret, _}}, Map.get(blocks_by_id, target))

        _ ->
          false
      end)

    assert br_to_ret?, "expected tag_switch merge to branch into a ret block"

    c = CLowerFunction.emit(plan)
    assert c =~ "switch (__plan_state)"
    assert c =~ "*out ="
    refute Regex.match?(~r/case ELMC_PLAN_STATE[^\n]+:\s*__plan_state = -1; break;\s*case ELMC_PLAN_STATE[^\n]+RETURN/s, c)
  end

  test "foldl tuple-arg lambda flattens to tupleArg + acc with dx/dy prelude" do
    decl = %{
      name: "patch",
      args: ["piece", "board"],
      expr: %{
        op: :qualified_call,
        target: "List.foldl",
        args: [
          %{
            op: :lambda,
            args: ["tupleArg"],
            body: %{
              name: "dx",
              op: :let_in,
              value_expr: %{
                op: :tuple_first_expr,
                arg: %{op: :var, name: "tupleArg"}
              },
              in_expr: %{
                name: "dy",
                op: :let_in,
                value_expr: %{
                  op: :tuple_second_expr,
                  arg: %{op: :var, name: "tupleArg"}
                },
                in_expr: %{
                  op: :lambda,
                  args: ["acc"],
                  body: %{
                    op: :call,
                    name: "__append__",
                    args: [%{op: :var, name: "acc"}, %{op: :var, name: "dx"}]
                  }
                }
              }
            }
          },
          %{op: :var, name: "board"},
          %{
            op: :list_literal,
            items: [
              %{op: :tuple2, left: %{op: :int_literal, value: 1}, right: %{op: :int_literal, value: 2}}
            ]
          }
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    lam = hd(plan.lambdas)
    entry = Enum.find(lam.blocks, &(&1.id == lam.entry_block))
    assert Enum.any?(entry.instrs, &(&1.op == :tuple_proj))
    assert Enum.any?(entry.instrs, &(&1.op == :call_runtime))
    assert :ok = Verify.run(plan)
  end

  test "list literal preserves source element order (cons last item first)" do
    decl = %{
      name: "xs",
      args: [],
      expr: %{
        op: :list_literal,
        items: [
          %{op: :int_literal, value: 1},
          %{op: :int_literal, value: 2},
          %{op: :int_literal, value: 3}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "plan_list_int_values_"
    assert c =~ "{ 1, 2, 3 }"
    assert c =~ "elmc_list_from_int_array"
  end

  test "Pebble.Ui.toUiNode lowers to retain on render-op list" do
    decl = %{
      name: "wrap",
      args: ["ops"],
      expr: %{
        op: :qualified_call,
        target: "Pebble.Ui.toUiNode",
        args: [%{op: :var, name: "ops"}]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: false)
    dump = Debug.dump(plan)
    assert dump =~ "retain"
    refute dump =~ "call_fn"
    assert :ok = Verify.run(plan)

    section = Lower.lower(plan)
    ops = [{:render_cmd, 0, [1, 2, 3]}]

    assert {:ok, ^ops} =
             Runtime.run_section(section, params: [ops], plan_key: {"Main", "wrap"})
  end

  test "unit tuple and Cmd.none lower for init-style pair" do
    decl = %{
      name: "init",
      args: ["_"],
      expr: %{
        op: :tuple2,
        left: %{op: :constructor_call, target: "()", args: []},
        right: %{op: :qualified_call, target: "Cmd.none", args: []}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "unit"
    assert dump =~ "pebble_cmd"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_unit()"
    assert c =~ "elmc_cmd_none()"
  end

  test "Sub.none lowers to pebble_sub with zero mask" do
    decl = %{
      name: "subs",
      args: ["_"],
      expr: %{op: :qualified_call, target: "Sub.none", args: []}
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    dump = Debug.dump(plan)
    assert dump =~ "pebble_sub"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_sub0"
  end

  test "nested record field access resolves width on container record, not global alias" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Pebble.Platform", "LaunchContext"} => ["reason", "watchModel", "watchProfileId", "screen", "hasMicrophone", "hasCompass", "supportsHealth"],
      {"Pebble.Platform", "LaunchScreen"} => ["width", "height", "shape", "colorMode"],
      {"Pebble.Ui.Resources", "AnimatedBitmapInfo"} => ["name", "resourceId", "width", "height"]
    })

    Process.put(:elmc_record_field_types, %{
      {"Pebble.Platform", "LaunchContext"} => %{
        "screen" => "LaunchScreen"
      },
      {"Pebble.Platform", "LaunchScreen"} => %{
        "width" => "Int",
        "height" => "Int"
      }
    })

    on_exit(fn ->
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_record_field_types)
    end)

    decl_map = %{
      {"Main", "init"} => %{
        name: "init",
        type: "Pebble.Platform.LaunchContext -> ( Main.Model, Cmd Msg )",
        args: ["context"],
        expr: %{
          op: :field_access,
          arg: %{
            op: :field_access,
            arg: %{op: :var, name: "context"},
            field: "screen"
          },
          field: "width"
        }
      }
    }

    assert {:ok, plan} = Function.lower(Map.fetch!(decl_map, {"Main", "init"}), "Main", decl_map, rc_required: true)

    [record_get_int] =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get_int))

    assert record_get_int.args[:field_index] =~ "0"
    refute record_get_int.args[:field_index] =~ "2"
    assert :ok = Verify.run(plan)
  end

  test "extensible record field access uses max index among known shapes" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Elm", "File"} => ["path", "contents", "warnings"],
      {"Url", "Url"} => ["protocol", "host", "port_", "path", "query", "fragment"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    decl_map = %{
      {"Route", "urlToRoute"} => %{
        name: "urlToRoute",
        type: "{url | path : String} -> Maybe Route",
        args: ["url"],
        expr: %{
          op: :field_access,
          arg: %{op: :var, name: "url"},
          field: "path"
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(Map.fetch!(decl_map, {"Route", "urlToRoute"}), "Route", decl_map,
               rc_required: true
             )

    [record_get] =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))

    assert record_get.args[:field_index] =~ "3"
    refute record_get.args[:field_index] =~ ~r/\b0\b/
    assert :ok = Verify.run(plan)
  end

  test "string inequality compare uses string mode not pointer equality" do
    decl_map = %{
      {"Route", "nonEmptySegment"} => %{
        name: "nonEmptySegment",
        type: "String -> Bool",
        args: ["item"],
        expr: %{
          op: :compare,
          kind: :neq,
          left: %{op: :var, name: "item"},
          right: %{op: :string_literal, value: ""}
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(
               Map.fetch!(decl_map, {"Route", "nonEmptySegment"}),
               "Route",
               decl_map,
               rc_required: true
             )

    compare =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(&(&1.op == :compare))

    assert compare.args[:mode] == :string
    assert compare.args[:kind] == :neq
    assert :ok = Verify.run(plan)
  end

  test "maybe_map field access uses typed Maybe payload record field index" do
    decl_map = %{
      {"Main", "usePath"} => %{
        name: "usePath",
        type: "Maybe { metadata : Int, pageUrl : Int, path : Int } -> Maybe Int",
        args: ["maybePagePath"],
        expr: %{
          op: :runtime_call,
          function: "elmc_maybe_map",
          args: [
            %{
              op: :lambda,
              args: ["x"],
              body: %{op: :field_access, arg: %{op: :var, name: "x"}, field: "path"}
            },
            %{op: :var, name: "maybePagePath"}
          ]
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(Map.fetch!(decl_map, {"Main", "usePath"}), "Main", decl_map,
               rc_required: true
             )

    [record_get] =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))

    assert record_get.args[:field_index] =~ "2"
    refute record_get.args[:field_index] =~ ~r/\b0\b/
    assert :ok = Verify.run(plan)
  end

  test "maybe_and_then field access uses typed Maybe payload record field index" do
    decl_map = %{
      {"Main", "useMetadata"} => %{
        name: "useMetadata",
        type: "Maybe { metadata : Int, pageUrl : Int, path : Int } -> Maybe Int",
        args: ["maybePagePath"],
        expr: %{
          op: :runtime_call,
          function: "elmc_maybe_and_then",
          args: [
            %{
              op: :lambda,
              args: ["x"],
              body: %{op: :field_access, arg: %{op: :var, name: "x"}, field: "metadata"}
            },
            %{op: :var, name: "maybePagePath"}
          ]
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(Map.fetch!(decl_map, {"Main", "useMetadata"}), "Main", decl_map,
               rc_required: true
             )

    [record_get] =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get))

    assert record_get.args[:field_index] =~ "0"
    assert :ok = Verify.run(plan)
  end

  test "Maybe.map2 reuses maybe via andThen + map on same param (qualified_call)" do
    # Mirrors elm_pebble_dev Main.init:
    #   Maybe.map2 Tuple.pair
    #     (Maybe.andThen .metadata maybePagePath)
    #     (Maybe.map .path maybePagePath)
    # Special-value lowering must not consume the param on andThen then borrow it on map.
    decl_map = %{
      {"Main", "pairFields"} => %{
        name: "pairFields",
        type: "Maybe { metadata : Maybe Int, path : Int } -> Maybe (Maybe Int, Int)",
        args: ["maybePagePath"],
        expr: %{
          op: :qualified_call,
          target: "Maybe.map2",
          args: [
            %{op: :qualified_ref, target: "Tuple.pair"},
            %{
              op: :qualified_call,
              target: "Maybe.andThen",
              args: [
                %{
                  op: :lambda,
                  args: ["fieldAccessorArg"],
                  body: %{
                    op: :field_access,
                    arg: "fieldAccessorArg",
                    field: "metadata"
                  }
                },
                %{op: :var, name: "maybePagePath"}
              ]
            },
            %{
              op: :qualified_call,
              target: "Maybe.map",
              args: [
                %{
                  op: :lambda,
                  args: ["fieldAccessorArg"],
                  body: %{
                    op: :field_access,
                    arg: "fieldAccessorArg",
                    field: "path"
                  }
                },
                %{op: :var, name: "maybePagePath"}
              ]
            }
          ]
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(Map.fetch!(decl_map, {"Main", "pairFields"}), "Main", decl_map,
               rc_required: false
             )

    assert :ok = Verify.run(plan)

    ops =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.map(& &1.op)

    assert :record_get in ops
    refute Enum.any?(plan.blocks, fn block ->
             Enum.any?(block.instrs, fn
               %{op: :call_runtime, args: %{builtin: :maybe_and_then}} -> true
               _ -> false
             end)
           end)
  end

  test "__apply__ field accessor uses applied value type for record field index" do
    Process.put(:elmc_record_alias_shapes, %{
      {"Main", "App"} => ["view", "head"],
      {"Pages.ProgramConfig", "ProgramConfig"} => ["init", "update", "view", "subscriptions"]
    })

    on_exit(fn -> Process.delete(:elmc_record_alias_shapes) end)

    decl_map = %{
      {"Main", "pickView"} => %{
        name: "pickView",
        type: "Main.App -> (Main.Model -> View.View msg)",
        args: ["app"],
        expr: %{
          op: :call,
          name: "__apply__",
          args: [
            %{
              op: :lambda,
              args: ["record"],
              body: %{op: :field_access, arg: %{op: :var, name: "record"}, field: "view"}
            },
            %{op: :var, name: "app"}
          ]
        }
      }
    }

    assert {:ok, plan} =
             Function.lower(Map.fetch!(decl_map, {"Main", "pickView"}), "Main", decl_map,
               rc_required: false
             )

    view_gets =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :record_get and Map.get(&1.args, :field) == "view"))

    assert view_gets != []
    assert Enum.all?(view_gets, fn instr -> String.starts_with?(instr.args[:field_index], "0") end)
    refute Enum.any?(view_gets, fn instr -> String.contains?(instr.args[:field_index], "3") end)
    assert :ok = Verify.run(plan)
  end
end
