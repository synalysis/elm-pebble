defmodule Elmx.DebugLogEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Stdlib

  test "Debug.log compiles via stdlib special call" do
    assert {:ok, code} = Stdlib.special_call("Debug.log", ~s("tag", value))
    assert code == "Elmx.Runtime.Core.Debug.log(\"tag\", value)"
  end

  test "qualified Debug.log in expression emits runtime call" do
    expr = %{
      op: :qualified_call,
      target: "Debug.log",
      args: [%{op: :string_literal, value: "x"}, %{op: :int_literal, value: 1}]
    }

    env = Emit.function_env("Main", []) |> Map.put(:module, "Main")
    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Core.Debug.log"
  end
end
