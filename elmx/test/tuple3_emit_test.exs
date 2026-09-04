defmodule Elmx.Tuple3EmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "official #3 emits a + nested pair payload" do
    expr = %{
      op: :tuple3,
      a: %{op: :int_literal, value: 1},
      b: %{op: :int_literal, value: 2},
      c: %{op: :int_literal, value: 3}
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) == "{1, {2, 3}}"
  end

  test "3-tuple case patterns match official nested-pair encoding" do
    expr = %{
      op: :case,
      subject: "triple",
      branches: [
        %{
          pattern: %{
            kind: :tuple,
            elements: [
              %{kind: :wildcard},
              %{kind: :var, name: "actual"},
              %{kind: :var, name: "expected"}
            ]
          },
          expr: %{op: :var, name: "actual"}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["triple"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{_, {actual, _expected}}"
    refute source =~ "{_, actual, expected}"
  end

  test "3-tuple of Just constructors nests each payload pair" do
    expr = %{
      op: :case,
      subject: "triple",
      branches: [
        %{
          pattern: %{
            kind: :tuple,
            elements: [
              %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "x"}},
              %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "y"}},
              %{kind: :constructor, name: "Just", arg_pattern: %{kind: :var, name: "z"}}
            ]
          },
          expr: %{op: :var, name: "x"}
        }
      ]
    }

    env =
      Emit.function_env("Main", ["triple"])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "{{:Just, x}, {{:Just, _y}, {:Just, _z}}}"
    refute source =~ "{:Just, x}, {:Just, y}, {:Just, z}"
  end
end
