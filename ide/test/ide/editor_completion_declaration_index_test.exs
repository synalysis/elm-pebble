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
    assert index.record_fields_by_type["Model"] == ["pageIndex"]
    assert index.field_types_by_type["Model"]["pageIndex"] == "Int"
    assert [%{name: "update", bindings: %{"msg" => "Msg", "model" => "Model"}}] =
             Enum.filter(index.function_scopes, &(&1.name == "update"))
  end

  test "indexes init parameter bindings from signature" do
    source = """
    module Main exposing (..)

    import Pebble.Platform as PebblePlatform

    type alias Model =
        { pageIndex : Int }

    init : PebblePlatform.LaunchContext -> Model
    init context =
        context
    """

    index = EditorCompletionDeclarationIndex.build(source)

    assert %{"PebblePlatform" => "Pebble.Platform"} = index.import_aliases

    assert [%{name: "init", bindings: %{"context" => "PebblePlatform.LaunchContext"}}] =
             Enum.filter(index.function_scopes, &(&1.name == "init"))
  end

  test "import alias parsing strips partial exposing suffix glued to alias" do
    source = "import Pebble.Storage as Storageeposing (\n"
    index = EditorCompletionDeclarationIndex.build(source)

    assert %{"Storage" => "Pebble.Storage"} = index.import_aliases
    refute Map.has_key?(index.import_aliases, "Storageeposing")
  end
end
