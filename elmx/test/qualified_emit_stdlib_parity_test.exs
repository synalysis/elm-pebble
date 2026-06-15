defmodule Elmx.QualifiedEmitStdlibParityTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib

  defp env do
    Emit.function_env("Main", ["f", "xs"])
    |> Map.put(:module, "Main")
    |> Map.put(:f, true)
    |> Map.put(:xs, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  @stdlib_only_targets [
    {"Dict.union", ["d1", "d2"], "dict_union"},
    {"Set.union", ["s1", "s2"], "set_union"},
    {"Array.map", ["f", "arr"], "array_map"}
  ]

  test "full arity List.map IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "List.map", args: [%{op: :var, name: "f"}, %{op: :var, name: "xs"}]}

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)

    assert {:ok, stdlib_code} = Stdlib.qualified_call("List.map", "f, xs")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code == "#{CodegenRefs.core()}.map(f, xs)"
  end

  test "Dict.get IR emit matches Stdlib.qualified_call" do
    expr = %{
      op: :qualified_call,
      target: "Dict.get",
      args: [%{op: :var, name: "k"}, %{op: :var, name: "d"}]
    }

    env =
      env()
      |> Map.put(:k, true)
      |> Map.put(:d, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("Dict.get", "k, d")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "String.map IR emit matches Stdlib.qualified_call" do
    expr = %{
      op: :qualified_call,
      target: "String.map",
      args: [%{op: :var, name: "f"}, %{op: :var, name: "text"}]
    }

    env = env() |> Map.put(:text, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("String.map", "f, text")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code =~ CodegenRefs.core_strings()
  end

  test "Task.map uses stdlib path in emit fallback before Basics" do
    expr = %{
      op: :qualified_call,
      target: "Task.map",
      args: [%{op: :var, name: "f"}, %{op: :var, name: "t"}]
    }

    env = env() |> Map.put(:t, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("Task.map", "f, t")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code =~ CodegenRefs.core_task()
  end

  test "Json.Decode.andThen emit fallback matches Stdlib.qualified_call" do
    args = [%{op: :var, name: "step"}]

    {emit_code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("Json.Decode.andThen", args, env(), 0)

    assert {:ok, stdlib_code} = Stdlib.qualified_call("Json.Decode.andThen", "step")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "partial String.split IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "String.split", args: [%{op: :var, name: "sep"}]}

    env = env() |> Map.put(:sep, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("String.split", "sep")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "partial List.filter IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "List.filter", args: [%{op: :var, name: "f"}]}

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("List.filter", "f")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "List.sum IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "List.sum", args: [%{op: :var, name: "xs"}]}

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("List.sum", "xs")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code == "#{CodegenRefs.core()}.list_sum(xs)"
  end

  test "String.lines IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "String.lines", args: [%{op: :var, name: "text"}]}

    env = env() |> Map.put(:text, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("String.lines", "text")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code == "#{CodegenRefs.core_strings()}.lines(text)"
  end

  test "List.indexedMap partial IR emit matches Stdlib.qualified_call" do
    expr = %{op: :qualified_call, target: "List.indexedMap", args: [%{op: :var, name: "f"}]}

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("List.indexedMap", "f")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code =~ ".indexed_map(f, elmx_list)"
  end

  test "emit fallback string path matches Stdlib.qualified_call for collection ops" do
    for {target, arg_names, fragment} <- @stdlib_only_targets do
      args = Enum.map(arg_names, &%{op: :var, name: &1})
      arg_code = Enum.join(arg_names, ", ")

      assert {:ok, stdlib_code} = Stdlib.qualified_call(target, arg_code)
      assert stdlib_code =~ fragment

      {emit_code, _, _} =
        QualifiedEmit.compile_qualified_call_fallback_string(target, args, env(), 0)

      emit_source = IO.iodata_to_binary(emit_code)
      assert emit_source =~ fragment
      assert emit_source =~ CodegenRefs.core_collections()
    end
  end

  test "Result.mapError IR fallback matches Stdlib.qualified_call" do
    expr = %{
      op: :qualified_call,
      target: "Result.mapError",
      args: [%{op: :var, name: "f"}, %{op: :var, name: "result"}]
    }

    env = env() |> Map.put(:result, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call_fallback(expr.target, expr.args, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("Result.mapError", "f, result")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code =~ CodegenRefs.maybe_result()
  end

  test "Json.Decode.string zero-arity emit fallback matches Stdlib.qualified_call" do
    {emit_code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("Json.Decode.string", [], env(), 0)

    assert {:ok, stdlib_code} = Stdlib.qualified_call("Json.Decode.string", "")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code == "#{CodegenRefs.json_decode()}.string()"
  end

  test "Basics.modBy unqualified emit matches Stdlib.qualified_call" do
    expr = %{
      op: :qualified_call,
      target: "Basics.modBy",
      args: [%{op: :var, name: "d"}, %{op: :var, name: "v"}]
    }

    env = env() |> Map.put(:d, true) |> Map.put(:v, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call_fallback(expr.target, expr.args, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("Basics.modBy", "d, v")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "String.append emit fallback matches Stdlib.qualified_call" do
    expr = %{
      op: :qualified_call,
      target: "String.append",
      args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
    }

    env = env() |> Map.put(:a, true) |> Map.put(:b, true)

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call_fallback(expr.target, expr.args, env, 0)
    assert {:ok, stdlib_code} = Stdlib.qualified_call("String.append", "a, b")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
    assert stdlib_code == "#{CodegenRefs.core()}.append(a, b)"
  end

  test "Basics.sin and Char.toUpper emit fallback match Stdlib.qualified_call" do
  env = env() |> Map.put(:theta, true) |> Map.put(:ch, true)

  sin_expr = %{op: :qualified_call, target: "Basics.sin", args: [%{op: :var, name: "theta"}]}

  {sin_emit, _, _} = QualifiedEmit.compile_qualified_call_fallback(sin_expr.target, sin_expr.args, env, 0)
  assert {:ok, sin_stdlib} = Stdlib.qualified_call("Basics.sin", "theta")
  assert IO.iodata_to_binary(sin_emit) == sin_stdlib
  assert sin_stdlib == "#{CodegenRefs.core_math()}.sin(theta)"

  char_expr = %{op: :qualified_call, target: "Char.toUpper", args: [%{op: :var, name: "ch"}]}

  {char_emit, _, _} =
    QualifiedEmit.compile_qualified_call_fallback(char_expr.target, char_expr.args, env, 0)

  assert {:ok, char_stdlib} = Stdlib.qualified_call("Char.toUpper", "ch")
  assert IO.iodata_to_binary(char_emit) == char_stdlib
  end

  test "Maybe.andThen partial emit fallback matches Stdlib.qualified_call" do
    args = [%{op: :var, name: "step"}]

    {emit_code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("Maybe.andThen", args, env(), 0)

    assert {:ok, stdlib_code} = Stdlib.qualified_call("Maybe.andThen", "step")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "Maybe.withDefault emit fallback matches Stdlib.qualified_call" do
    args = [%{op: :var, name: "default"}, %{op: :var, name: "maybe"}]
    env = env() |> Map.put(:default, true) |> Map.put(:maybe, true)

    {emit_code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("Maybe.withDefault", args, env, 0)

    assert {:ok, stdlib_code} = Stdlib.qualified_call("Maybe.withDefault", "default, maybe")
    assert IO.iodata_to_binary(emit_code) == stdlib_code
  end

  test "executor contract string is stable" do
    assert Elmx.Runtime.Executor.contract() == "elmx.runtime_executor.v1"
  end
end
