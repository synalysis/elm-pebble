defmodule Elmx.CorpusPackagesEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit

  defp env do
    Emit.function_env("Main", ["a", "b", "bytes", "pid", "msg"])
    |> Map.put(:module, "Main")
    |> Map.put(:a, true)
    |> Map.put(:b, true)
    |> Map.put(:bytes, true)
    |> Map.put(:pid, true)
    |> Map.put(:msg, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "Binary.FixedWidth xor/and emit Bitwise ops" do
  expr = %{
    op: :qualified_call,
    target: "Binary.FixedWidth.xor",
    args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
  }

  {code, env, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
  assert IO.iodata_to_binary(code) == "Bitwise.bxor(a, b)"
  assert Map.get(env, :uses_bitwise)
  end

  test "Bytes.width emits byte_size/1" do
    expr = %{op: :qualified_call, target: "Bytes.width", args: [%{op: :var, name: "bytes"}]}

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert IO.iodata_to_binary(code) == "byte_size(bytes)"
  end

  test "partial Bytes.width emits unary byte_size closure" do
    expr = %{op: :qualified_call, target: "Bytes.width", args: []}

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert IO.iodata_to_binary(code) == "fn elmx_bytes -> byte_size(elmx_bytes) end"
  end

  test "Actor.send emits succeed task for dead-send compatibility" do
    expr = %{
      op: :qualified_call,
      target: "Actor.send",
      args: [%{op: :var, name: "pid"}, %{op: :var, name: "msg"}]
    }

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert IO.iodata_to_binary(code) =~ ".succeed("
  end

  test "Cli.program passes through program record for compile gate" do
    spec = %{
      op: :record_literal,
      fields: [
        %{name: "init", expr: %{op: :var, name: "init"}},
        %{name: "update", expr: %{op: :var, name: "update"}},
        %{name: "subscriptions", expr: %{op: :lambda, args: ["_"], body: %{op: :int_literal, value: 0}}}
      ]
    }

    expr = %{op: :qualified_call, target: "Cli.program", args: [spec]}

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    assert IO.iodata_to_binary(code) =~ "init"
    assert IO.iodata_to_binary(code) =~ "update"
  end
end
