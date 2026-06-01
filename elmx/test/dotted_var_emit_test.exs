defmodule Elmx.DottedVarEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  defp base_env(module, params) do
    Emit.function_env(module, params)
    |> Map.put(:module, module)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "dotted var in record update base becomes Map.get chain" do
    expr = %{
      op: :record_update,
      base: %{op: :var, name: "model.player"},
      fields: [
        %{
          name: "levelTag",
          expr: %{op: :string_literal, value: ":L1"}
        }
      ]
    }

    env = base_env("Main", ["model"])
    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ ~s|Map.put(Map.get(model, "player"), "levelTag", ":L1")|
    refute source =~ "elmx_fn_Main_model"
  end

  test "tuple bind let uses non-underscore parameter name" do
    expr = %{
      op: :let_in,
      name: "__tupleBind_scene_finished",
      value_expr: %{op: :tuple2, left: %{op: :int_literal, value: 1}, right: %{op: :int_literal, value: 2}},
      in_expr: %{
        op: :case,
        subject: "__tupleBind_scene_finished",
        branches: [
          %{
            pattern: %{kind: :var, name: "scene"},
            expr: %{op: :var, name: "scene"}
          }
        ]
      }
    }

    env = base_env("Main", [])
    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn tupleBind_scene_finished ->"
    refute source =~ "fn __tupleBind_"
  end
end
