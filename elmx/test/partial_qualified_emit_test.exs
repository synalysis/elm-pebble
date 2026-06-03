defmodule Elmx.PartialQualifiedEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit
  alias Elmx.Runtime.Stdlib

  defp env do
    Emit.function_env("Main", ["f"])
    |> Map.put(:module, "Main")
    |> Map.put(:f, true)
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "compile_list_qualified partial List.map emits lambda" do
    expr = %{
      op: :qualified_call,
      target: "List.map",
      args: [%{op: :var, name: "f"}]
    }

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn elmx_list ->"
    assert source =~ "Core.map"
    assert source =~ "f"
  end

  test "Stdlib.qualified_call partial List.filter" do
    assert {:ok, code} = Stdlib.qualified_call("List.filter", "f")
    assert code == "fn elmx_list -> Elmx.Runtime.Core.filter(f, elmx_list) end"
  end

  test "Stdlib.qualified_call partial Dict.insert" do
    assert {:ok, code} = Stdlib.qualified_call("Dict.insert", "1, v")

    assert code ==
             "fn elmx_dict -> Elmx.Runtime.Core.Collections.dict_insert(1, v, elmx_dict) end"
  end

  test "compile_list_qualified partial List.foldl emits two-arg lambda" do
    expr = %{
      op: :qualified_call,
      target: "List.foldl",
      args: [%{op: :var, name: "f"}]
    }

    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn elmx_acc, elmx_list ->"
    assert source =~ "Core.foldl"
  end

  test "emit fallback string path delegates to Stdlib.qualified_call" do
    args = [%{op: :var, name: "text"}]

    {code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("String.lines", args, env(), 0)

    assert IO.iodata_to_binary(code) =~ "lines"
    assert Stdlib.handles_qualified?("String.lines")
  end

  test "Stdlib.qualified_call partial Json.Decode.andThen and list" do
    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.andThen", "step")
    assert code == "fn elmx_dec -> Elmx.Runtime.Json.Decode.and_then(step, elmx_dec) end"

    assert {:ok, code} = Stdlib.qualified_call("Json.Decode.list", "")
    assert code == "fn elmx_inner -> Elmx.Runtime.Json.Decode.list(elmx_inner) end"
  end

  test "emit fallback delegates Result.mapError to Stdlib.qualified_call" do
    args = [%{op: :var, name: "f"}, %{op: :var, name: "result"}]

    {code, _, _} =
      QualifiedEmit.compile_qualified_call_fallback_string("Result.mapError", args, env(), 0)

    source = IO.iodata_to_binary(code)
    assert source =~ "result_map_error"
    assert Stdlib.handles_qualified?("Result.mapError")
    assert {:ok, special} = Stdlib.qualified_call("Result.mapError", "f, result")
    assert special =~ "result_map_error"
  end
end
