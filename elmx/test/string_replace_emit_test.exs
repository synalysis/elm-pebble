defmodule Elmx.StringReplaceEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.Core.Strings
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Stdlib

  test "runtime intrinsic replaces substrings" do
    assert {:ok, "a.b.c"} = Generator.apply("elmc_string_replace", ["-", ".", "a-b-c"])
  end

  test "Strings.replace matches Elm argument order" do
    assert Strings.replace("-", ".", "a-b-c") == "a.b.c"
  end

  test "qualified String.replace emits Core.Strings" do
    expr = %{
      op: :qualified_call,
      target: "String.replace",
      args: [
        %{op: :string_literal, value: "-"},
        %{op: :string_literal, value: "."},
        %{op: :string_literal, value: "a-b"}
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:function_arities, %{})
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:constructor_lookup, %{})

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "Core.Strings.replace"
  end

  test "partial String.replace via Stdlib.Qualified" do
    assert {:ok, code} = Stdlib.qualified_call("String.replace", "\"-\", \".\"")

    assert code ==
             "fn elmx_str -> Elmx.Runtime.Core.Strings.replace(\"-\", \".\", elmx_str) end"
  end

  test "String.split emit and partial" do
    expr = %{
      op: :qualified_call,
      target: "String.split",
      args: [
        %{op: :string_literal, value: ","},
        %{op: :string_literal, value: "a,b"}
      ]
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:function_arities, %{})
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:constructor_lookup, %{})

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "Core.Strings.split"

    assert {:ok, partial} = Stdlib.qualified_call("String.split", "\"-\"")
    assert partial == "fn elmx_str -> Elmx.Runtime.Core.Strings.split(\"-\", elmx_str) end"
  end
end
