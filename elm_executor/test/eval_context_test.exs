defmodule ElmExecutor.Runtime.SemanticExecutor.EvalContextTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor.EvalContext

  @contract %{"module" => "Main", "msg_constructors" => ["Tick"]}

  test "contract/1 prefers debugger_contract over elm_introspect" do
    ctx = %{debugger_contract: %{"module" => "New"}, elm_introspect: %{"module" => "Old"}}
    assert %{"module" => "New"} = EvalContext.contract(ctx)
  end

  test "contract/1 falls back to elm_introspect" do
    assert @contract = EvalContext.contract(%{elm_introspect: @contract})
  end

  test "put_contract/2 writes both keys" do
    ctx = EvalContext.put_contract(%{}, @contract)
    assert ctx.debugger_contract == @contract
    assert ctx.elm_introspect == @contract
  end
end
