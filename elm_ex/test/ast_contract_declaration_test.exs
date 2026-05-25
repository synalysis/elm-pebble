defmodule ElmEx.AstContractDeclarationTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{AstContract, Module}

  test "validate_module accepts function and union declarations" do
    module = %Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "main",
          args: [],
          expr: %{op: :int_literal, value: 0},
          span: %{start_line: 1, end_line: 1}
        },
        %{
          kind: :union,
          name: "Msg",
          constructors: [%{name: "Tick", arg: nil}],
          span: %{start_line: 3, end_line: 4}
        }
      ]
    }

    assert :ok = AstContract.validate_module(module)
  end
end
