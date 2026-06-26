defmodule Elmx.QualifiedPipelineTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib

  defp env do
    Emit.function_env("Main", ["x", "y", "f", "t"])
    |> Map.put(:module, "Main")
    |> Map.put(:x, true)
    |> Map.put(:y, true)
    |> Map.put(:f, true)
    |> Map.put(:t, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "emit qualified resolution paths produce CodegenRefs-backed code" do
    list_map =
      QualifiedEmit.compile_qualified_call(
        %{op: :qualified_call, target: "List.map", args: [%{op: :var, name: "f"}, %{op: :var, name: "x"}]},
        env(),
        0
      )
      |> elem(0)
      |> IO.iodata_to_binary()

    assert list_map == "#{CodegenRefs.core()}.map(f, x)"

    task_map =
      QualifiedEmit.compile_qualified_call(
        %{op: :qualified_call, target: "Task.map", args: [%{op: :var, name: "f"}, %{op: :var, name: "t"}]},
        env(),
        0
      )
      |> elem(0)
      |> IO.iodata_to_binary()

    assert task_map == "#{CodegenRefs.core_task()}.map(f, t)"

    math_unary =
      QualifiedEmit.compile_qualified_call(
        %{op: :qualified_call, target: "Basics.isInfinite", args: [%{op: :var, name: "x"}]},
        env(),
        0
      )
      |> elem(0)
      |> IO.iodata_to_binary()

    assert math_unary == "#{CodegenRefs.core_math()}.is_infinite(x)"

    assert Stdlib.handles_qualified?("List.map")
    assert Stdlib.handles_qualified?("Task.andThen")
    assert Stdlib.handles_qualified?("Basics.isInfinite")
    assert Stdlib.handles_qualified?("Char.isDigit")
  end

  test "homogeneous qualified pipeline prefix compiles to Enum.reduce" do
    targets = Enum.map(1..20, fn _ -> "Basics.identity" end)

    expr =
      Enum.reduce(Enum.reverse(targets), %{op: :int_literal, value: 0}, fn target, inner ->
        %{op: :qualified_call, target: target, args: [inner]}
      end)

    env = env()

    {emit_code, _, _} = QualifiedEmit.compile_qualified_call(expr, env, 0)
    code = IO.iodata_to_binary(emit_code)

    assert code =~ "Apply.repeat1"
  end
end
