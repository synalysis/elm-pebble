defmodule Elmc.ListAppendRcTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RuntimeCall.Core, as: RuntimeCall
  alias Elmc.Backend.CCodegen.ValueSlots

  test "list ++ in RC mode uses elmc_list_append with CHECK_RC" do
    ValueSlots.reset(epilogue_lifo: true)

    append_expr = %{
      op: :runtime_call,
      function: "elmc_append",
      args: [
        %{op: :list_literal, items: [%{op: :int_literal, value: 1}]},
        %{op: :list_literal, items: [%{op: :int_literal, value: 2}]}
      ]
    }

    out = RcRuntimeEmit.function_out_ref()

    env =
      %{}
      |> Map.put(:__rc_catch__, true)
      |> Map.put(:__rc_required__, true)
      |> Map.put(:__branch_out__, out)
      |> Map.put(:__declared_outs__, MapSet.new([out]))

    {code, result, _counter} = RuntimeCall.compile(append_expr, env, 0)

    assert result == out
    assert code =~ "Rc = elmc_list_append("
    assert code =~ "CHECK_RC(Rc)"
    refute code =~ "elmc_append("
    refute code =~ "owned[1] = elmc_list_append"
    refute code =~ "ElmcValue *tmp_"
  end

  test "list ++ branch assignment routes append through RC allocator" do
    ValueSlots.reset(epilogue_lifo: true)

    append_expr = %{
      op: :runtime_call,
      function: "elmc_append",
      args: [
        %{op: :var, name: "left"},
        %{op: :var, name: "right"}
      ]
    }

    out = RcRuntimeEmit.function_out_ref()

    env =
      %{"left" => "owned[0]", "right" => "owned[1]"}
      |> Map.put(:__rc_catch__, true)
      |> Map.put(:__rc_required__, true)
      |> Map.put(:__branch_out__, out)
      |> Map.put(:__declared_outs__, MapSet.new([out]))

    {code, assignment, _counter} =
      CaseCompile.branch_assignment(append_expr, out, env, 2)

    body = code <> assignment

    assert body =~ "Rc = elmc_list_append("
    assert body =~ "CHECK_RC(Rc)"
    refute body =~ "elmc_append("
    refute body =~ "owned[3] = elmc_list_append"
  end
end
