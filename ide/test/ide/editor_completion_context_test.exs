defmodule Ide.EditorCompletionContextTest do
  use ExUnit.Case, async: true

  alias Ide.EditorCompletionContext

  test "classifies record field access" do
    source = "update model = model.pa"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :record_field_access
    assert context.qualifier == "model"
    assert context.prefix == "pa"
  end

  test "classifies nested record field access" do
    source = "init context = context.screen."
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :record_field_access
    assert context.qualifier == "context.screen"
  end

  test "classifies record field access after binary operator" do
    source = """
    hasPiece model =
        model.pieceKind >= 0 && model.
    """

    context =
      EditorCompletionContext.analyze(%{
        source: source,
        offset: String.length(source)
      })

    assert context.kind == :record_field_access
    assert context.qualifier == "model"
    assert context.prefix == ""
  end

  test "classifies partial record field access after binary operator" do
    source = "hasPiece model = model.pieceKind >= 0 && model.pi"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :record_field_access
    assert context.qualifier == "model"
    assert context.prefix == "pi"
  end

  test "classifies uppercase qualified access as module access" do
    source = "main = List."
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :module_qualified_access
    assert context.qualifier == "List"
    assert context.prefix == ""
  end

  test "classifies type annotation after a colon" do
    source = "newFunction : I"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :type_annotation
    assert context.prefix == "I"
  end

  test "classifies normal expressions as value expressions" do
    source = "update model = ma"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :value_expression
    assert context.prefix == "ma"
  end
end
