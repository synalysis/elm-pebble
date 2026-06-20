defmodule Elmx.PartialConstructorEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "partial_constructor emits curried closure building tagged tuple" do
    expr = %{
      op: :partial_constructor,
      target: "GotListing",
      tag: 1,
      args: [%{op: :string_literal, value: "test_dir1"}],
      arity: 2
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:emit_mode, :library)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn elmx_p1 ->"
    assert source =~ "{:GotListing, \"test_dir1\", elmx_p1}"
  end
end
