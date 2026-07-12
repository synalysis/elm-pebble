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
    assert c =~ "elmc_record_update_index_cow_drop"
    assert c =~ "elmc_retain"
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
    assert dump =~ "builtin: :retain"
    assert :ok = Verify.run(plan)

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_union_tag_matches"
    assert c =~ "goto elmc_plan_block_"
    assert c =~ "*out = owned[1];"
    refute c =~ "elmc_retain(owned["
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

    assert Enum.any?(plan.blocks, fn block ->
             match?({:br, _}, block.terminator) and
               Enum.any?(block.instrs, fn
                 %{op: :call_runtime, args: %{builtin: :retain}} -> true
                 _ -> false
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
    assert c =~ "elmc_cmd0"
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
end
