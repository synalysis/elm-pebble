defmodule Ide.EditorCompletionDeclarationIndexTest do
  use ExUnit.Case, async: true

  alias Ide.EditorCompletionDeclarationIndex

  test "indexes types values constructors and record fields" do
    source = """
    module Main exposing (..)

    type alias Model =
        { pageIndex : Int }

    type Msg
        = Next
        | SetPage Int

    update : Msg -> Model -> Model
    update msg model =
        model
    """

    index = EditorCompletionDeclarationIndex.build(source)

    assert "Model" in index.types
    assert "Msg" in index.types
    assert "Int" in index.types
    assert "update" in index.values
    assert "Next" in index.constructors
    assert "SetPage" in index.constructors
    assert "pageIndex" in index.record_fields
  end
end
