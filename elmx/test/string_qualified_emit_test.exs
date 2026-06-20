defmodule Elmx.StringQualifiedEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Stdlib

  defp env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:function_arities, %{})
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:constructor_lookup, %{})
  end

  defp emit(target, args) do
    expr = %{op: :qualified_call, target: target, args: args}

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    IO.iodata_to_binary(code)
  end

  test "String.join and contains emit Core.Strings" do
    assert emit("String.join", [
             %{op: :string_literal, value: ","},
             %{op: :list_literal, items: [%{op: :string_literal, value: "a"}]}
           ]) =~ "Strings.join"

    assert emit("String.contains", [
             %{op: :string_literal, value: "b"},
             %{op: :string_literal, value: "abc"}
           ]) =~ "Strings.contains"
  end

  test "Basics.compare rewrites to Core.basics_compare" do
    source =
      emit("Basics.compare", [
        %{op: :int_literal, value: 1},
        %{op: :int_literal, value: 2}
      ])

    assert source =~ "Elmx.Runtime.Core.basics_compare(1, 2)"
    assert Core.basics_compare(1, 2) == :LT
  end

  test "partial String.join via Stdlib.Qualified" do
    assert {:ok, code} = Stdlib.qualified_call("String.join", "\"-\"")
    assert code =~ "fn elmx_list ->"
    assert code =~ "Strings.join"
  end

  test "String.length and reverse emit Core.Strings" do
    text = %{op: :string_literal, value: "abc"}

    assert emit("String.length", [text]) =~ "Strings.length_val"
    assert emit("String.reverse", [text]) =~ "Strings.reverse"
  end

  test "String.toInt and fromFloat emit Core.Strings" do
    text = %{op: :string_literal, value: "42"}
    f = %{op: :float_literal, value: 3.5}

    assert emit("String.toInt", [text]) =~ "Strings.to_int"
    assert emit("String.fromFloat", [f]) =~ "Strings.from_float"
  end

  test "Dict.get uses collections IR path not string fallback" do
    key = %{op: :int_literal, value: 1}
    dict = %{op: :list_literal, items: []}

    source = emit("Dict.get", [key, dict])
    assert source =~ "Core.Collections.dict_get"
    refute source =~ "runtime_dispatch"
  end

  test "String.fromList and Dict.map use direct Core paths" do
    chars = %{op: :list_literal, items: [%{op: :string_literal, value: "a"}]}
    dict = %{op: :list_literal, items: []}
    fun = %{op: :var, name: "f"}

    assert emit("String.fromList", [chars]) =~ "Strings.from_list"

    expr = %{op: :qualified_call, target: "Dict.map", args: [fun, dict]}
    env = env() |> Map.put(:f, true)
    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "Collections.dict_map"
  end
end
