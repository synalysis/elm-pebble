defmodule Elmx.AppendEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Core

  test "infix append emits Core.append not list ++" do
    expr = %{
      op: :call,
      name: "__append__",
      args: [
        %{op: :string_literal, value: "hi"},
        %{op: :string_literal, value: "!"}
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "Elmx.Runtime.Core.append"
    refute source =~ " ++ "
  end

  test "Core.append concatenates strings and appends lists" do
    assert Core.append("a", "b") == "ab"
    assert Core.append([1], [2]) == [1, 2]
    assert Core.append(1, 2) == "12"
  end
end
