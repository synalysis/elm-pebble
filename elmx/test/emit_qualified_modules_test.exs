defmodule Elmx.EmitQualifiedModulesTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.List, as: QualifiedList
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.String, as: QualifiedString
  alias Elmx.Runtime.CodegenRefs

  defp env do
    Emit.function_env("Main", ["f", "xs", "text"])
    |> Map.put(:module, "Main")
    |> Map.put(:f, true)
    |> Map.put(:xs, true)
    |> Map.put(:text, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "domain modules compile List and String qualified calls" do
    list_expr = %{
      op: :qualified_call,
      target: "List.map",
      args: [%{op: :var, name: "f"}, %{op: :var, name: "xs"}]
    }

    assert {:ok, code, _, _} = QualifiedList.compile("List.map", list_expr.args, env(), 0)
    assert IO.iodata_to_binary(code) == "#{CodegenRefs.core()}.map(f, xs)"

    str_expr = %{
      op: :qualified_call,
      target: "String.lines",
      args: [%{op: :var, name: "text"}]
    }

    assert {:ok, code, _, _} = QualifiedString.compile("String.lines", str_expr.args, env(), 0)
    assert IO.iodata_to_binary(code) == "#{CodegenRefs.core_strings()}.lines(text)"
  end

  test "orchestrator delegates to domain modules and stdlib fallback" do
    list_expr = %{op: :qualified_call, target: "List.filter", args: [%{op: :var, name: "f"}]}

    {code, _, _} = QualifiedEmit.compile_qualified_call(list_expr, env(), 0)
    assert IO.iodata_to_binary(code) =~ "fn elmx_list ->"

    math_expr = %{op: :qualified_call, target: "Basics.sin", args: [%{op: :var, name: "f"}]}

    {code, _, _} = QualifiedEmit.compile_qualified_call_fallback(math_expr.target, math_expr.args, env(), 0)
    assert IO.iodata_to_binary(code) == "#{CodegenRefs.core_math()}.sin(f)"
  end
end
