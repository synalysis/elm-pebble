defmodule Elmx.OversaturatedQualifiedTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Calls
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Backend.OversaturatedQualified

  defp env do
    Emit.function_env("ApLR", ["ops", "g"])
    |> Map.put(:module, "ApLR")
    |> Map.put(:ops, true)
    |> Map.put(:g, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "Tuple.first with extra args applies after tuple projection" do
    expr = %{
      op: :qualified_call,
      target: "Tuple.first",
      args: [
        %{op: :var, name: "ops"},
        %{op: :var, name: "g"},
        %{op: :int_literal, value: 7}
      ]
    }

    normalized = OversaturatedQualified.normalize(expr)
    assert %{op: :call, name: "__apply__"} = normalized

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    code = IO.iodata_to_binary(emit_code)

    assert code =~ "elem(ops, 0)"
    assert code =~ "Apply.apply1"
    refute code =~ "elem(ops, g, 7"
  end

  test "homogeneous long |> chains compile to Apply.repeat1" do
    steps = Enum.map(1..20, fn _ -> %{op: :var, name: "add1"} end)
    base = %{op: :int_literal, value: 0}

    expr =
      Enum.reduce(steps, base, fn step, acc ->
        %{op: :call, name: "|>", args: [acc, step]}
      end)

    env =
      Emit.function_env("LongPipeline", ["add1"])
      |> Map.put(:module, "LongPipeline")
      |> Map.put(:add1, true)
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{"add1" => 1})

    {emit_code, _, _} = Calls.compile_call(expr, env, 0)
    code = IO.iodata_to_binary(emit_code)

    assert code =~ "Apply.repeat1(add1, 20, 0)"
    refute code =~ "elmx_pipe_slot_"
  end

  test "heterogeneous long |> chains flatten to iterative apply block" do
    steps =
      Enum.map(1..20, fn i ->
        %{op: :var, name: if(rem(i, 2) == 0, do: "add1", else: "add2")}
      end)

    base = %{op: :int_literal, value: 0}

    expr =
      Enum.reduce(steps, base, fn step, acc ->
        %{op: :call, name: "|>", args: [acc, step]}
      end)

    env =
      Emit.function_env("LongPipeline", ["add1", "add2"])
      |> Map.put(:module, "LongPipeline")
      |> Map.put(:add1, true)
      |> Map.put(:add2, true)
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{"add1" => 1, "add2" => 1})

    {emit_code, _, _} = Calls.compile_call(expr, env, 0)
    code = IO.iodata_to_binary(emit_code)

    assert code =~ "elmx_pipe_slot_"
    assert code =~ "Apply.apply1(add1, elmx_pipe_slot_"
    refute String.match?(code, ~r/Apply\.apply1\(Apply\.apply1/)
  end
end
