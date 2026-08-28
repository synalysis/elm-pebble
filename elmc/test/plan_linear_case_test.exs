defmodule Elmc.PlanLinearCaseTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function

  @moduletag :plan_surface

  test "three-arm int case uses guarded switch CFG" do
    decl = %{
      name: "pick",
      args: ["n"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "n"},
        branches: [
          %{pattern: %{kind: :int, value: 1}, expr: %{op: :int_literal, value: 10}},
          %{pattern: %{kind: :int, value: 2}, expr: %{op: :int_literal, value: 20}},
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "pick"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "switch_tag" or text =~ "br_if"
  end

  test "qualified constructor case lowers" do
    Process.put(:elmc_constructor_tags, %{"Maybe.Nothing" => 0, "Maybe.Just" => 1})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "fromMaybe",
      args: ["m"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "m"},
        branches: [
          %{
            pattern: %{kind: :qualified_constructor, name: "Maybe.Nothing"},
            expr: %{op: :int_literal, value: 0}
          },
          %{
            pattern: %{kind: :var, name: "x"},
            expr: %{op: :var, name: "x"}
          }
        ]
      }
    }

    decl_map = %{{"Probe", "fromMaybe"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    assert plan != nil
  end

  test "single-branch tuple wildcard case lowers" do
    decl = %{
      name: "bindCmd",
      args: ["pair"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "pair"},
        branches: [
          %{
            pattern: %{
              kind: :tuple,
              elements: [%{kind: :wildcard}, %{kind: :var, name: "cmd"}]
            },
            expr: %{op: :var, name: "cmd"}
          }
        ]
      }
    }

    decl_map = %{{"Probe", "bindCmd"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    assert inspect(plan.blocks) =~ "tuple_proj"
  end

  test "fixed-length cons-nil case with list literal arm verifies" do
    decl = %{
      name: "polygonLines",
      args: ["color", "points"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "points"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "List.::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "a"},
                  %{
                    kind: :constructor,
                    name: "::",
                    resolved_name: "List.::",
                    arg_pattern: %{
                      kind: :tuple,
                      elements: [
                        %{kind: :var, name: "b"},
                        %{
                          kind: :constructor,
                          name: "::",
                          resolved_name: "List.::",
                          arg_pattern: %{
                            kind: :tuple,
                            elements: [
                              %{kind: :var, name: "c"},
                              %{kind: :constructor, name: "[]", resolved_name: "[]", arg_pattern: nil}
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            },
            expr: %{
              op: :list_literal,
              items: [
                %{op: :int_literal, value: 1},
                %{op: :int_literal, value: 2},
                %{op: :int_literal, value: 3}
              ]
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :list_literal, items: []}}
        ]
      }
    }

    decl_map = %{{"Probe", "polygonLines"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "list_head"
    refute text =~ "dest: :fn_out"
  end

  test "guarded cons case unwraps Maybe from list_head for cons bind" do
    decl = %{
      name: "headWord",
      args: ["words"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "words"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "List.::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :var, name: "first"},
                  %{kind: :var, name: "rest"}
                ]
              }
            },
            expr: %{op: :var, name: "first"}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :string_literal, value: ""}}
        ]
      }
    }

    decl_map = %{{"Probe", "headWord"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "list_head"
    assert text =~ "maybe_just_payload"
  end

  test "guarded cons case with string literal head tests the literal" do
    # Route.segmentsToRoute-style: [ "wasm" ] / [ "f-a-q" ] must not match on
    # nonempty alone — otherwise every singleton list hits the first arm.
    decl = %{
      name: "segmentsToRoute",
      args: ["segments"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "segments"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "List.::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :string, value: "wasm"},
                  %{kind: :constructor, name: "[]", resolved_name: "[]", arg_pattern: nil}
                ]
              }
            },
            expr: %{op: :int_literal, value: 13}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "::",
              resolved_name: "List.::",
              arg_pattern: %{
                kind: :tuple,
                elements: [
                  %{kind: :string, value: "f-a-q"},
                  %{kind: :constructor, name: "[]", resolved_name: "[]", arg_pattern: nil}
                ]
              }
            },
            expr: %{op: :int_literal, value: 6}
          },
          %{
            pattern: %{kind: :constructor, name: "[]", resolved_name: "[]", arg_pattern: nil},
            expr: %{op: :int_literal, value: 14}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "segmentsToRoute"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "test_string_literal"
    assert text =~ "list_head"
    assert text =~ ~s(literal: "wasm")
  end

  test "constructor case with string payload pattern lowers" do
    Process.put(:elmc_constructor_tags, %{"Companion.Types.PushString" => 7})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "matchString",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "PushString",
              tag: 7,
              resolved_name: "Companion.Types.PushString",
              arg_pattern: %{kind: :string, value: "elm"}
            },
            expr: %{op: :int_literal, value: 1}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "matchString"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "test_string_literal" or text =~ "union_payload"
  end

  test "three-arm tagged constructor case uses tag switch" do
    Process.put(:elmc_constructor_tags, %{"Msg.A" => 1, "Msg.B" => 2, "Msg.C" => 3})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "route",
      args: ["msg"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.A", tag: 1},
            expr: %{op: :int_literal, value: 10}
          },
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.B", tag: 2},
            expr: %{op: :int_literal, value: 20}
          },
          %{
            pattern: %{kind: :qualified_constructor, name: "Msg.C", tag: 3},
            expr: %{op: :int_literal, value: 30}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    decl_map = %{{"Probe", "route"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "switch_tag" or text =~ "switch_ctor_tag"
  end

  test "exhaustive constructor case tests the last arm tag (no untagged default)" do
    # Scene3d.getViewBounds-style: last ctor is Transformed with payload binds.
    # Untagged default peels garbage as Transformed and can recurse forever.
    Process.put(:elmc_constructor_tags, %{
      "Node.Empty" => 1,
      "Node.Group" => 6,
      "Node.Transformed" => 7
    })

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "classify",
      args: ["node"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "node"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "Empty",
              resolved_name: "Node.Empty",
              tag: 1
            },
            expr: %{op: :int_literal, value: 1}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "Group",
              resolved_name: "Node.Group",
              tag: 6,
              arg_pattern: %{kind: :var, name: "kids"}
            },
            expr: %{op: :int_literal, value: 6}
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "Transformed",
              resolved_name: "Node.Transformed",
              tag: 7,
              arg_pattern: %{
                kind: :tuple,
                elements: [%{kind: :var, name: "t"}, %{kind: :var, name: "child"}]
              }
            },
            expr: %{op: :int_literal, value: 7}
          }
        ]
      }
    }

    decl_map = %{{"Probe", "classify"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)

    switch_arms =
      plan.blocks
      |> Enum.find_value(fn block ->
        case block.terminator do
          {:switch_tag, _subject, arms, _default} -> arms
          _ -> nil
        end
      end)

    # Exhaustive constructor arms use native switch dispatch (not linear br_if chains).
    assert switch_arms |> Enum.map(&elem(&1, 0)) == [1, 6, 7]
    assert length(switch_arms) == 3

    br_ifs =
      plan.blocks
      |> Enum.count(fn block -> match?({:br_if, _, _, _}, block.terminator) end)

    assert br_ifs == 0
  end

  test "single-constructor peel does not tag-test (untyped unwrap)" do
    # (Quantity r) = q and (Entity node) must peel payload even when the value is a
    # bare float/record or shares global tag 1 with unrelated types.
    # Real IR often uses `bind:` (not arg_pattern var); TagSwitch used to claim
    # those and emit switch_tag → fallthrough Int 0 on mismatch.
    Process.put(:elmc_constructor_tags, %{"Quantity.Quantity" => 1})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    for pattern <- [
          %{
            kind: :constructor,
            name: "Quantity",
            resolved_name: "Quantity.Quantity",
            tag: 1,
            arg_pattern: %{kind: :var, name: "r"}
          },
          %{
            kind: :constructor,
            name: "Quantity",
            resolved_name: "Quantity.Quantity",
            tag: 1,
            bind: "r"
          }
        ] do
      decl = %{
        name: "unwrapQuantity",
        args: ["q"],
        expr: %{
          op: :case,
          subject: %{op: :var, name: "q"},
          branches: [%{pattern: pattern, expr: %{op: :var, name: "r"}}]
        }
      }

      decl_map = %{{"Probe", "unwrapQuantity"} => decl}

      assert {:ok, plan} = Elmc.Backend.Plan.Lower.Function.lower(decl, "Probe", decl_map, rc_required: true)

      text = inspect(plan.blocks)
      refute text =~ "union_tag_matches"
      refute text =~ "switch_tag"
      refute Enum.any?(plan.blocks, fn block -> match?({:br_if, _, _, _}, block.terminator) end)
      assert text =~ "union_payload" or text =~ "tuple_proj"
    end
  end

  test "ctor payload bind is not treated as passive impossible-default" do
    Process.put(:elmc_constructor_tags, %{"UseTexture" => 0, "UseColor" => 1})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    # Scene3d textured/bumpy mesh shape: UseTexture payload is captured by a
    # nested lambda. Impossible-default must not recompile that arm under a
    # wildcard (which left materialColorData unbound).
    decl = %{
      name: "texturedMesh",
      args: ["mat", "y"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "mat"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "UseTexture",
              tag: 0,
              bind: "materialColorData",
              arg_pattern: nil
            },
            expr: %{
              op: :lambda,
              args: ["z"],
              body: %{
                op: :call,
                name: "__apply__",
                args: [
                  %{op: :var, name: "materialColorData"},
                  %{op: :var, name: "z"}
                ]
              }
            }
          },
          %{
            pattern: %{
              kind: :constructor,
              name: "UseColor",
              tag: 1,
              bind: "constantColor",
              arg_pattern: nil
            },
            expr: %{
              op: :lambda,
              args: ["z"],
              body: %{op: :var, name: "constantColor"}
            }
          }
        ]
      }
    }

    decl_map = %{{"Probe", "texturedMesh"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    assert is_list(plan.lambdas)
    assert length(plan.lambdas) >= 1
  end

  test "n-ary __apply__ left-folds in plan Call" do
    decl = %{
      name: "apply3",
      args: ["f", "a", "b", "c"],
      expr: %{
        op: :call,
        name: "__apply__",
        args: [
          %{op: :var, name: "f"},
          %{op: :var, name: "a"},
          %{op: :var, name: "b"},
          %{op: :var, name: "c"}
        ]
      }
    }

    decl_map = %{{"Probe", "apply3"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "call_closure"
  end

  test "exhaustive constructor case result is owned on every merge predecessor" do
    Process.put(:elmc_constructor_tags, %{"Main.Left" => 1, "Main.Right" => 2})
    Process.put(:elmc_record_alias_shapes, %{
      {"Main", "Model"} => ["best", "score"]
    })

    on_exit(fn ->
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_record_alias_shapes)
    end)

    decl = %{
      name: "pick",
      args: ["msg", "model"],
      expr: %{
        op: :let_in,
        name: "next",
        value_expr: %{
          op: :case,
          subject: %{op: :var, name: "msg"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Left", resolved_name: "Main.Left", tag: 1},
              expr: %{op: :var, name: "model"}
            },
            %{
              pattern: %{kind: :constructor, name: "Right", resolved_name: "Main.Right", tag: 2},
              expr: %{op: :var, name: "model"}
            }
          ]
        },
        in_expr: %{
          op: :field_access,
          arg: %{op: :var, name: "next"},
          field: "best"
        }
      }
    }

    decl_map = %{{"Main", "pick"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true)

    switch =
      Enum.find(plan.blocks, fn
        %{terminator: {:switch_tag, _, _, _}} -> true
        _ -> false
      end)

    assert match?(%{terminator: {:switch_tag, _, _, default}} when is_integer(default), switch)
    {:switch_tag, _subj, arms, default_id} = switch.terminator
    arm_ids = Enum.map(arms, fn
      {_, id} -> id
      {_, id, _} -> id
    end)

    merge_id =
      plan.blocks
      |> Enum.find_value(fn
        %{id: id, instrs: instrs} ->
          if Enum.any?(instrs, &(&1.op == :record_get)), do: id

        _ ->
          nil
      end)

    refute default_id in arm_ids
    refute default_id == merge_id

    default_block = Enum.find(plan.blocks, &(&1.id == default_id))
    assert default_block.terminator == {:ret, :fn_out}
  end

  test "exhaustive constructor sink verifies when owned values are live" do
    Process.put(:elmc_constructor_tags, %{"Main.Left" => 1, "Main.Right" => 2})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "label",
      args: ["msg"],
      expr: %{
        op: :let_in,
        name: "s",
        value_expr: %{
          op: :call,
          name: "__append__",
          args: [
            %{op: :string_literal, value: "a"},
            %{op: :string_literal, value: "b"}
          ]
        },
        in_expr: %{
          op: :case,
          subject: %{op: :var, name: "msg"},
          branches: [
            %{
              pattern: %{kind: :constructor, name: "Left", resolved_name: "Main.Left", tag: 1},
              expr: %{op: :var, name: "s"}
            },
            %{
              pattern: %{kind: :constructor, name: "Right", resolved_name: "Main.Right", tag: 2},
              expr: %{op: :var, name: "s"}
            }
          ]
        }
      }
    }

    decl_map = %{{"Main", "label"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true)
    assert Enum.any?(plan.blocks, fn
             %{terminator: {:ret, :fn_out}, instrs: instrs} ->
               Enum.any?(instrs, fn
                 %{op: :call_runtime, args: %{builtin: builtin}}
                 when builtin in [:unreachable, :unsupported] ->
                   true

                 _ ->
                   false
               end)

             _ ->
               false
           end)
  end

  test "VirtualDom.on/2 lowers to html_cmd event" do
    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})
    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)

    decl = %{
      name: "onCustom",
      args: ["event", "handler"],
      expr: %{
        op: :qualified_call,
        target: "Elm.Kernel.VirtualDom.on",
        args: [%{op: :var, name: "event"}, %{op: :var, name: "handler"}]
      }
    }

    decl_map = %{{"Probe", "onCustom"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "html_cmd"
  end

  test "nested 3-tuple of Justs lowers without heap tuple or stub" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    just = fn name ->
      %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: name}}
    end

    decl = %{
      name: "versionTriple",
      args: ["ma", "mb", "mc"],
      expr: %{
        op: :case,
        subject: %{
          op: :tuple2,
          left: %{op: :var, name: "ma"},
          right: %{
            op: :tuple2,
            left: %{op: :var, name: "mb"},
            right: %{op: :var, name: "mc"}
          }
        },
        branches: [
          %{
            pattern: %{
              kind: :tuple,
              elements: [
                just.("x"),
                %{kind: :tuple, elements: [just.("y"), just.("z")]}
              ]
            },
            expr: %{op: :var, name: "x"}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "bool_and"
    refute text =~ "unsupported"

    c = Elmc.Backend.C.Lower.Function.emit(plan)
    refute c =~ "RC_ERR_UNSUPPORTED"
    assert c =~ "elmc_maybe_is_nothing"
  end

  test "let-bound 3-tuple of Justs peels to tuple2 subject" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    just = fn name ->
      %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: name}}
    end

    triple = %{
      op: :tuple2,
      left: %{op: :var, name: "ma"},
      right: %{
        op: :tuple2,
        left: %{op: :var, name: "mb"},
        right: %{op: :var, name: "mc"}
      }
    }

    decl = %{
      name: "versionTripleLet",
      args: ["ma", "mb", "mc"],
      expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: triple,
        in_expr: %{
          op: :case,
          subject: %{op: :var, name: "caseSubject"},
          branches: [
            %{
              pattern: %{
                kind: :tuple,
                elements: [
                  just.("x"),
                  %{kind: :tuple, elements: [just.("y"), just.("z")]}
                ]
              },
              expr: %{op: :var, name: "y"}
            },
            %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: -1}}
          ]
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "bool_and"
    refute text =~ "unsupported"
  end

  test "3-tuple Just case with duplicated wildcard default lowers" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0, "Maybe.Just" => 1})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    just_bind = fn name ->
      %{
        kind: :constructor,
        name: "Just",
        tag: 1,
        bind: name,
        arg_pattern: nil,
        resolved_name: "Maybe.Just"
      }
    end

    fail = %{
      op: :qualified_call,
      target: "Json.Decode.fail",
      args: [%{op: :string_literal, value: "bad version"}]
    }

    decl = %{
      name: "versionDecoderLam",
      args: ["ma", "mb", "mc"],
      expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: %{
          op: :tuple2,
          left: %{op: :var, name: "ma"},
          right: %{
            op: :tuple2,
            left: %{op: :var, name: "mb"},
            right: %{op: :var, name: "mc"}
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
                  just_bind.("x"),
                  %{kind: :tuple, elements: [just_bind.("y"), just_bind.("z")]}
                ]
              },
              expr: %{
                op: :qualified_call,
                target: "Json.Decode.succeed",
                args: [
                  %{
                    op: :tuple2,
                    left: %{op: :var, name: "x"},
                    right: %{
                      op: :tuple2,
                      left: %{op: :var, name: "y"},
                      right: %{op: :var, name: "z"}
                    }
                  }
                ]
              }
            },
            %{pattern: %{kind: :wildcard}, expr: fail},
            %{pattern: %{kind: :wildcard}, expr: fail}
          ]
        }
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", %{}, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "bool_and"
    refute text =~ "unsupported"

    c = Elmc.Backend.C.Lower.Function.emit(plan)
    refute c =~ "RC_ERR_UNSUPPORTED"
  end
end
