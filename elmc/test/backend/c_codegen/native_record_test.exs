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
    assert code =~ "elmc_record_new_take(2"
    assert code =~ "elmc_new_string(direct_label)"
    assert code =~ "elmc_new_int(direct_x)"
  end
end
