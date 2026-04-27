defmodule Elmc.FrontendAstContractTest do
  use ExUnit.Case

  alias ElmEx.Frontend.AstContract
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module

  test "validator rejects function definitions without expr op" do
    module = %Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: [
        %{
          kind: :function_definition,
          name: "f",
          args: [],
          expr: %{},
          span: %{start_line: 1, end_line: 1}
        }
      ]
    }

    assert {:error, %{kind: :ast_contract_error, reason: :missing_expr_op}} =
             AstContract.validate_module(module)
  end

  test "validator rejects declarations without valid span" do
    module = %Module{
      name: "Main",
      path: "Main.elm",
      imports: [],
      declarations: [
        %{kind: :function_signature, name: "x", type: "Int", span: %{start_line: 0, end_line: 0}}
      ]
    }

    assert {:error, %{kind: :ast_contract_error, reason: :invalid_span}} =
             AstContract.validate_module(module)
  end

  test "generated parser emits spans for function definitions" do
    fixture = Path.expand("fixtures/simple_project/src/Main.elm", __DIR__)
    assert {:ok, module} = GeneratedParser.parse_file(fixture)

    function_defs =
      module.declarations
      |> Enum.filter(&(&1.kind == :function_definition))

    assert function_defs != []

    assert Enum.all?(function_defs, fn decl ->
             is_map(decl[:span]) and is_integer(decl.span.start_line)
           end)
  end

  test "generated parser emits spans for signatures, aliases and unions" do
    fixture = Path.expand("fixtures/simple_project/src/Pebble/Ui.elm", __DIR__)
    assert {:ok, module} = GeneratedParser.parse_file(fixture)

    covered =
      module.declarations
      |> Enum.filter(&(&1.kind in [:function_signature, :type_alias, :union]))

    assert covered != []

    assert Enum.all?(covered, fn decl ->
             is_map(decl[:span]) and is_integer(decl.span.start_line) and
               is_integer(decl.span.end_line) and decl.span.end_line >= decl.span.start_line
           end)
  end
end
