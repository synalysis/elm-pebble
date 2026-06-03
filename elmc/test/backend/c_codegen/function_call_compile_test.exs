defmodule Elmc.Backend.CCodegen.FunctionCallCompileTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.FunctionCallCompile

  test "compile_var boxes native record bindings with elmc_record_new_ints" do
    env = %{
      "layout" => {:native_record,
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
    assert code =~ "elmc_record_new_ints(4"
    assert code =~ "direct_native_record_layout_x_1"
    assert code =~ "\"x\""
    assert code =~ "\"gap\""
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
      assert code =~ "elmc_record_new_take(2"
      assert code =~ "elmc_new_string(direct_label)"
    after
      Process.delete(:elmc_record_alias_shapes)
      Process.delete(:elmc_record_field_types)
    end
  end

  test "compile_var boxes native records with mixed field types via record_new_take" do
    env = %{
      "layout" => {:native_record,
       %{
         "x" => "direct_x",
         "label" => "direct_label"
       }},
      __record_shapes__: %{"layout" => ["x", "label"]},
      __var_types__: %{"layout" => "BoardLayout"}
    }

    Process.put(:elmc_record_field_types, %{{"Main", "BoardLayout"} => %{"x" => "Int", "label" => "String"}})

    try do
      {code, var, _} = FunctionCallCompile.compile_var("layout", env, 0)

      assert var == "tmp_1"
      assert code =~ "elmc_record_new_take(2"
      assert code =~ "elmc_new_int(direct_x)"
      assert code =~ "elmc_new_string(direct_label)"
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
end
