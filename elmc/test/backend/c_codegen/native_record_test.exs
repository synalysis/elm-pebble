defmodule Elmc.Backend.CCodegen.NativeRecordTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord
  alias Elmc.Backend.CCodegen.FunctionCallCompile

  test "field_entries accepts mixed record literal without type alias metadata" do
    env = %{__module__: "Main"}

    expr = %{
      op: :record_literal,
      fields: [
        %{name: "x", expr: %{op: :int_literal, value: 1}},
        %{name: "label", expr: %{op: :string_literal, value: "ok"}}
      ]
    }

    assert {:ok, entries} = NativeRecord.field_entries(expr, env)
    assert length(entries) == 2
  end

  test "emit_fields stores per-field kinds for mixed native record lets" do
    env = %{
      "model" => "model_var",
      __module__: "Main",
      __program_decls__: %{}
    }

    value_expr = %{
      op: :record_literal,
      fields: [
        %{name: "x", expr: %{op: :int_literal, value: 4}},
        %{name: "label", expr: %{op: :string_literal, value: "hi"}}
      ]
    }

    assert {:ok, code, body_env, _} = NativeRecord.emit_fields("cfg", value_expr, env, 0)
    assert code =~ "direct_native_record_cfg_label"
    assert code =~ "const char *"
    assert get_in(body_env, [:__record_field_kinds__, "cfg", "label"]) == "String"
    assert get_in(body_env, [:__record_field_kinds__, "cfg", "x"]) == "Int"
  end

  test "emit_fields omits redundant zero init before immediate assignment" do
    env = %{__module__: "Main"}

    value_expr = %{
      op: :record_literal,
      fields: [
        %{name: "x", expr: %{op: :int_literal, value: 4}},
        %{name: "gap", expr: %{op: :int_literal, value: 2}}
      ]
    }

    assert {:ok, code, _, _} = NativeRecord.emit_fields("layout", value_expr, env, 0)
    refute code =~ ~r/elmc_int_t direct_native_record_layout_\w+_\d+ = 0;/
    assert code =~ ~r/const elmc_int_t direct_native_record_layout_x_\d+ = 4;/
    assert code =~ ~r/const elmc_int_t direct_native_record_layout_gap_\d+ = 2;/
  end

  test "emit_hoisted_if_fields supports mixed int and string branch fields" do
    env = %{__module__: "Main"}

    cond_expr = %{
      op: :qualified_call,
      target: "Platform.displayShapeIsRound",
      args: [%{op: :var, name: "model"}]
    }

    value_expr = %{
      op: :record_literal,
      fields: [
        %{
          name: "x",
          expr: %{
            op: :direct_native_if,
            cond: cond_expr,
            then_expr: %{op: :int_literal, value: 1},
            else_expr: %{op: :int_literal, value: 2}
          }
        },
        %{
          name: "label",
          expr: %{
            op: :direct_native_if,
            cond: cond_expr,
            then_expr: %{op: :string_literal, value: "round"},
            else_expr: %{op: :string_literal, value: "rect"}
          }
        }
      ]
    }

    assert {:ok, code, body_env, _} =
             NativeRecord.emit_fields("layout", value_expr, env, 0)

    refute code =~ ~r/elmc_int_t direct_native_record_branch__then_x_\d+ = 0;/
    refute code =~ ~r/elmc_int_t direct_native_record_branch__else_x_\d+ = 0;/
    assert code =~ ~r/const elmc_int_t direct_native_record_branch__then_x_\d+ = 1;/
    assert code =~ ~r/const elmc_int_t direct_native_record_branch__else_x_\d+ = 2;/
    assert code =~ "direct_native_record_branch__then_label"
    assert code =~ "direct_native_record_branch__else_label"
    assert code =~ "const char *direct_native_record_layout_label"
    assert code =~ "const elmc_int_t direct_native_record_layout_x"
    assert get_in(body_env, [:__record_field_kinds__, "layout", "label"]) == "String"
    assert get_in(body_env, [:__record_field_kinds__, "layout", "x"]) == "Int"
  end

  test "compile_var boxes mixed native record using stored field kinds" do
    env = %{
      "cfg" => {:native_record, %{"x" => "direct_x", "label" => "direct_label"}},
      __record_shapes__: %{"cfg" => ["label", "x"]},
      __record_field_kinds__: %{"cfg" => %{"x" => "Int", "label" => "String"}}
    }

    {code, var, _} = FunctionCallCompile.compile_var("cfg", env, 0)

    assert var == "tmp_1"
    assert code =~ "elmc_record_new_values_take(2"
    assert code =~ "elmc_new_string_take(direct_label)"
    assert code =~ "elmc_new_int_take(direct_x)"
    refute code =~ "\"label\""
  end

  test "debug branch_span_key matches board size add after cell substitution" do
    cell_ref = %{op: :c_int_expr, value: "direct_native_record_branch__then_cell_2"}

    board_size = %{
      op: :call,
      name: "__add__",
      args: [
        %{op: :call, name: "__mul__", args: [cell_ref, %{op: :int_literal, value: 4}]},
        %{op: :call, name: "__mul__", args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]}
      ]
    }

    refs = %{"cell" => "direct_native_record_branch__then_cell_2", "gap" => "direct_native_record_branch__then_gap_2"}

    sources = %{
      "gap" => %{op: :int_literal, value: 2},
      "cell" => %{op: :int_literal, value: 10}
    }

    assert {:ok, {"cell", 4, "gap", 3}, "cell", 4, "gap", 3} =
             NativeRecord.debug_branch_span_key(board_size, refs, sources)
  end

  test "branch span hoists cell*4 + gap*3 shared across x and y siblings" do
    env = %{
      __module__: "Main",
      __hoisted_native_ints_enabled__: true,
      __program_decls__: %{}
    }

    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.delete(:elmc_hoisted_native_ints)

    cond = %{op: :bool_literal, value: true}

    cell_formula = %{
      op: :call,
      name: "__idiv__",
      args: [
        %{
          op: :call,
          name: "__sub__",
          args: [
            %{op: :int_literal, value: 90},
            %{op: :call, name: "__mul__", args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]}
          ]
        },
        %{op: :int_literal, value: 4}
      ]
    }

    board_size = %{
      op: :call,
      name: "__add__",
      args: [
        %{
          op: :call,
          name: "__mul__",
          args: [cell_formula, %{op: :int_literal, value: 4}]
        },
        %{
          op: :call,
          name: "__mul__",
          args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]
        }
      ]
    }

    center = fn screen ->
      %{
        op: :call,
        name: "__idiv__",
        args: [
          %{
            op: :call,
            name: "__sub__",
            args: [%{op: :int_literal, value: screen}, board_size]
          },
          %{op: :int_literal, value: 2}
        ]
      }
    end

    value_expr = %{
      op: :record_literal,
      fields: [
        %{
          name: "gap",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: %{op: :int_literal, value: 2},
            else_expr: %{op: :int_literal, value: 3}
          }
        },
        %{
          name: "cell",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: cell_formula,
            else_expr: %{op: :int_literal, value: 20}
          }
        },
        %{
          name: "x",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: center.(144),
            else_expr: %{op: :int_literal, value: 0}
          }
        },
        %{
          name: "y",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: center.(168),
            else_expr: %{op: :int_literal, value: 0}
          }
        }
      ]
    }

    assert {:ok, code, _, _} = NativeRecord.emit_fields("layout", value_expr, env, 0)

    assert code =~ "direct_native_record_branch_span_"
    assert code =~ "direct_native_record_branch__then_cell_"

    then_x =
      code
      |> String.split("direct_native_record_branch__then_x_")
      |> Enum.at(1, "")
      |> String.split(";")
      |> hd()

    refute then_x =~ "direct_native_record_branch__then_cell_"
  after
    Process.delete(:elmc_hoisted_native_ints_scope)
    Process.delete(:elmc_hoisted_native_ints)
  end

  test "branch span hoists cell*4 + literal gap*3 after cell subexpr substitution" do
    env = %{
      __module__: "Main",
      __hoisted_native_ints_enabled__: true,
      __program_decls__: %{}
    }

    Process.put(:elmc_hoisted_native_ints_scope, true)
    Process.delete(:elmc_hoisted_native_ints)

    cond = %{op: :bool_literal, value: true}

    cell_formula = %{
      op: :call,
      name: "__idiv__",
      args: [
        %{
          op: :call,
          name: "__sub__",
          args: [
            %{
              op: :call,
              name: "__idiv__",
              args: [
                %{
                  op: :call,
                  name: "__mul__",
                  args: [%{op: :int_literal, value: 100}, %{op: :int_literal, value: 2}]
                },
                %{op: :int_literal, value: 3}
              ]
            },
            %{op: :call, name: "__mul__", args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]}
          ]
        },
        %{op: :int_literal, value: 4}
      ]
    }

    board_size = %{
      op: :call,
      name: "__add__",
      args: [
        %{
          op: :call,
          name: "__mul__",
          args: [cell_formula, %{op: :int_literal, value: 4}]
        },
        %{
          op: :call,
          name: "__mul__",
          args: [%{op: :int_literal, value: 2}, %{op: :int_literal, value: 3}]
        }
      ]
    }

    center = fn screen ->
      %{
        op: :call,
        name: "__idiv__",
        args: [
          %{
            op: :call,
            name: "__sub__",
            args: [%{op: :int_literal, value: screen}, board_size]
          },
          %{op: :int_literal, value: 2}
        ]
      }
    end

    value_expr = %{
      op: :record_literal,
      fields: [
        %{
          name: "gap",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: %{op: :int_literal, value: 2},
            else_expr: %{op: :int_literal, value: 3}
          }
        },
        %{
          name: "cell",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: cell_formula,
            else_expr: %{op: :int_literal, value: 20}
          }
        },
        %{
          name: "x",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: center.(144),
            else_expr: %{op: :int_literal, value: 0}
          }
        },
        %{
          name: "y",
          expr: %{
            op: :direct_native_if,
            cond: cond,
            then_expr: center.(168),
            else_expr: %{op: :int_literal, value: 0}
          }
        }
      ]
    }

    assert {:ok, code, _, _} = NativeRecord.emit_fields("layout", value_expr, env, 0)
    assert code =~ "direct_native_record_branch_span_"
  after
    Process.delete(:elmc_hoisted_native_ints_scope)
    Process.delete(:elmc_hoisted_native_ints)
  end
end
