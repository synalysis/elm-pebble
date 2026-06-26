defmodule ElmEx.IR.PipeChainTest do
  use ExUnit.Case, async: true

  alias ElmEx.IR.PipeChain

  test "desugar rebuilds nested qualified_call pipe applications" do
    base = %{op: :int_literal, value: 0}
    add1 = %{op: :var, name: "add1"}

    chain = %{
      op: :pipe_chain,
      steps: [add1, add1],
      base: base
    }

  desugared = PipeChain.desugar(chain)

    assert %{
             op: :call,
             name: "add1",
             args: [
               %{
                 op: :call,
                 name: "add1",
                 args: [%{op: :int_literal, value: 0}]
               }
             ]
           } = desugared
  end

  test "smart desugar keeps long homogeneous pipe_chain flat" do
    base = %{op: :int_literal, value: 0}
    add1 = %{op: :var, name: "add1"}
    steps = List.duplicate(add1, 20)

    chain = %{op: :pipe_chain, steps: steps, base: base}

    assert %{op: :pipe_chain, steps: ^steps} = PipeChain.desugar(chain)
  end

  test "desugar saturates qualified_call steps with accumulator argument" do
    chain = %{
      op: :pipe_chain,
      steps: [%{op: :qualified_call, target: "Tuple.mapFirst", args: [%{op: :var, name: "f"}]}],
      base: %{op: :var, name: "tuple"}
    }

    assert %{
             op: :qualified_call,
             target: "Tuple.mapFirst",
             args: [%{op: :var, name: "f"}, %{op: :var, name: "tuple"}]
           } = PipeChain.desugar(chain)
  end
end
