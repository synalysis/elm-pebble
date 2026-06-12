defmodule Elmc.Backend.CCodegen.FunctionCallCompileTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.FunctionCallCompile

  test "compile_var boxes native record bindings with field-id ints" do
    env = %{
      "layout" =>
        {:native_record,
         %{
           "x" => "direct_native_record_layout_x_1",
           "y" => "direct_native_record_layout_y_2",
           "cell" => "direct_native_record_layout_cell_3",
           "gap" => "direct_native_record_layout_gap_4"
         }},
      __record_shapes__: %{
        "layout" => ["x", "y", "cell", "gap"]
      }
    }

    {code, var, next} = FunctionCallCompile.compile_var("layout", env, 10)

    assert var == "tmp_11"
    assert next == 11
    assert code =~ "elmc_record_new_values_ints_take(4"
    refute code =~ "rec_field_ids_"
    assert code =~ "direct_native_record_layout_x_1"
    refute code =~ "\"x\""
    refute code =~ "\"gap\""
  end

  test "compile_var infers record type from field shape for mixed boxing" do
    Process.put(:elmc_record_alias_shapes, %{{"Main", "MixedLayout"} => ["label", "x"]})

    Process.put(:elmc_record_field_types, %{
      {"Main", "MixedLayout"} => %{"x" => "Int", "label" => "String"}
    })

    try do
      env = %{
        "layout" => {:native_record, %{"x" => "direct_x", "label" => "direct_label"}},
        __record_shapes__: %{"layout" => ["x", "label"]}
      }

      {code, var, _} = FunctionCallCompile.compile_var("layout", env, 0)

      assert var == "tmp_1"
      assert code =~ "elmc_record_new_values_take(2"
      assert code =~ "elmc_new_string_take(direct_label)"
      refute code =~ "\"label\""
    after
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_record_field_types)
    end
  end

  test "compile_var boxes native records with mixed field types via field IDs" do
    env = %{
      "layout" =>
        {:native_record,
         %{
           "x" => "direct_x",
           "label" => "direct_label"
         }},
      __record_shapes__: %{"layout" => ["x", "label"]},
      __var_types__: %{"layout" => "BoardLayout"}
    }

    Process.put(:elmc_record_field_types, %{
      {"Main", "BoardLayout"} => %{"x" => "Int", "label" => "String"}
    })

    try do
      {code, var, _} = FunctionCallCompile.compile_var("layout", env, 0)

      assert var == "tmp_1"
      assert code =~ "elmc_record_new_values_take(2"
      assert code =~ "elmc_new_int_take(direct_x)"
      assert code =~ "elmc_new_string_take(direct_label)"
      refute code =~ "\"label\""
    after
      Process.delete(:elmc_record_field_types)
    end
  end

  test "compile boxes forward_ref bindings via elmc_forward_ref_get" do
    {code, var, _} =
      FunctionCallCompile.compile_var("g", %{"g" => {:forward_ref, "letrec_ref_g_1"}}, 0)

    assert var == "tmp_1"
    assert code =~ "elmc_forward_ref_get(letrec_ref_g_1)"
  end

  test "compile call with fewer than arity args emits partial closure" do
    env = %{
      __module__: "Main",
      __function_arities__: %{{"Main", "add3"} => 3}
    }

    {code, var, _} =
      FunctionCallCompile.compile("Main", "add3", [%{op: :int_literal, value: 1}], env, 0)

    assert code =~ "elmc_partial_ref"
    assert code =~ "elmc_closure_new"
    assert var =~ "tmp_"
  end

  test "compile_var retains existing ElmcValue bindings" do
    {code, var, _} =
      FunctionCallCompile.compile_var("model", %{"model" => "existing_model_ptr"}, 0)

    assert var == "tmp_1"
    assert code =~ "existing_model_ptr"
    assert code =~ "elmc_retain"
  end

  test "borrow_arg callees pass let-bound locals without retain temps" do
    env =
      %{
        "tileIndex" => "tmp_index",
        "tileValue" => "tmp_value",
        "cells" => "cells"
      }
      |> Map.put(:__module__, "Main")
      |> Map.put(:__program_decls__, %{
        {"Main", "setCell"} => %{
          name: "setCell",
          args: ["index", "newValue", "cells"],
          ownership: [:borrow_arg, :retain_result]
        }
      })
      |> Map.put(:__function_arities__, %{{"Main", "setCell"} => 3})
      |> Map.put(:__direct_call_targets__, MapSet.new([{"Main", "setCell"}]))

    {code, _out, _} =
      FunctionCallCompile.compile(
        "Main",
        "setCell",
        [
          %{op: :var, name: "tileIndex"},
          %{op: :var, name: "tileValue"},
          %{op: :var, name: "cells"}
        ],
        env,
        2
      )

    source = IO.iodata_to_binary(code)

    assert source =~ "elmc_fn_Main_setCell(tmp_index, tmp_value, cells)"
    refute source =~ "elmc_retain(tmp_index)"
    refute source =~ "elmc_retain(tmp_value)"
    refute source =~ "elmc_release(tmp_index)"
    refute source =~ "elmc_release(tmp_value)"
  end

  test "borrow_arg operands pass record fields without retained getter temps" do
    env = %{
      "model" => "model",
      __record_shapes__: %{"model" => ["cells", "seed"]}
    }

    field_expr = %{op: :field_access, arg: %{op: :var, name: "model"}, field: "seed"}
    compact_field_expr = %{op: :field_access, arg: "model", field: "cells"}

    {borrow_code, borrow_ref, borrow_next, borrow_passthrough?} =
      FunctionCallCompile.compile_call_operand_inner(field_expr, env, 4, borrow_args?: true)

    assert borrow_code == ""
    assert borrow_ref == "ELMC_RECORD_GET_INDEX(model, 1 /* seed */)"
    assert borrow_next == 4
    assert borrow_passthrough?

    {compact_code, compact_ref, compact_next, compact_passthrough?} =
      FunctionCallCompile.compile_call_operand_inner(compact_field_expr, env, 4,
        borrow_args?: true
      )

    assert compact_code == ""
    assert compact_ref == "ELMC_RECORD_GET_INDEX(model, 0 /* cells */)"
    assert compact_next == 4
    assert compact_passthrough?

    {owned_code, owned_ref, owned_next, owned_passthrough?} =
      FunctionCallCompile.compile_call_operand_inner(field_expr, env, 4, borrow_args?: false)

    assert owned_ref == "tmp_5"
    assert owned_next == 5
    refute owned_passthrough?
    assert owned_code =~ "elmc_record_get_index(model, 1 /* seed */)"
  end

  test "borrow_arg boxed calls pass record fields directly in wrapper ABI" do
    env =
      %{
        "model" => "model",
        "cells" => "tmp_5",
        __record_shapes__: %{"model" => ["cells", "seed"]}
      }
      |> Map.put(:__module__, "Main")
      |> Map.put(:__program_decls__, %{
        {"Main", "spawnTileWithSeed"} => %{
          name: "spawnTileWithSeed",
          args: ["seed", "cells"],
          ownership: [:borrow_arg, :retain_result]
        }
      })
      |> Map.put(:__function_arities__, %{{"Main", "spawnTileWithSeed"} => 2})

    {code, _out, _} =
      FunctionCallCompile.compile(
        "Main",
        "spawnTileWithSeed",
        [
          %{op: :field_access, arg: "model", field: "seed"},
          %{op: :var, name: "cells"}
        ],
        env,
        13
      )

    source = IO.iodata_to_binary(code)

    assert source =~
             "ElmcValue *call_args_14[2] = { ELMC_RECORD_GET_INDEX(model, 1 /* seed */), tmp_5 }"

    refute source =~ "elmc_record_get_index(model, 1 /* seed */)"
    refute source =~ "elmc_release(tmp_13)"
  end
end
