defmodule Ide.EditorCompletionTest do
  use ExUnit.Case, async: true

  alias Ide.EditorCompletion

  test "aggregates parser, tokenizer, package, dependency, and keyword candidates" do
    parser_payload = %{
      metadata: %{
        module: "Main",
        imports: ["Html", "String"],
        ports: ["sendPort"],
        module_exposing: ["update", "Model"],
        import_entries: [
          %{"module" => "List", "as" => "L", "exposing" => ["map", "foldl"]}
        ]
      }
    }

    token_tokens = [
      %{class: "identifier", text: "update"},
      %{class: "type_identifier", text: "Model"},
      %{class: "field_identifier", text: "minute"},
      %{class: "comment", text: "-- not a symbol"}
    ]

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "m",
        parser_payload: parser_payload,
        token_tokens: token_tokens,
        package_doc_index: %{"Maybe" => "elm/core", "Html.Attributes" => "elm/html"},
        editor_doc_packages: [%{package: "elm/html", modules: ["Html.Events", "Html.Attributes"]}],
        direct_dependencies: [%{name: "elm/core"}],
        indirect_dependencies: [%{name: "elm/time"}],
        limit: 50
      })

    labels = Enum.map(suggestions, & &1.label)

    assert "map" in labels
    assert "Model" in labels
    assert "minute" in labels
    assert "Maybe" in labels
    assert "module" in labels
  end

  test "prefers parser symbols before generic sources" do
    parser_payload = %{
      metadata: %{
        module: "Main",
        imports: ["Maybe"],
        ports: [],
        module_exposing: [],
        import_entries: []
      }
    }

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "ma",
        parser_payload: parser_payload,
        token_tokens: [%{class: "identifier", text: "map"}],
        package_doc_index: %{"Map" => "elm/core"},
        limit: 10
      })

    assert Enum.at(suggestions, 0).label == "Main"
  end

  test "includes alias keyword for type alias flow" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "a",
        parser_payload: nil,
        token_tokens: [],
        package_doc_index: %{},
        limit: 20
      })

    assert Enum.any?(suggestions, &(&1.label == "alias"))
  end

  test "strips field accessor dot when completing after an existing dot" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "p",
        context_kind: :record_field_access,
        declaration_index: %{record_fields: ["pageIndex"]},
        limit: 10
      })

    assert [%{label: "pageIndex", insert_text: "pageIndex", source: "record/type-alias"}] =
             suggestions
  end

  test "dot access completions are limited to record fields" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :record_field_access,
        parser_payload: %{
          metadata: %{module_exposing: ["update"], imports: [], import_entries: []}
        },
        token_tokens: [
          %{class: "identifier", text: "update"},
          %{class: "field_identifier", text: ".tokenOnly"}
        ],
        package_doc_index: %{"Maybe" => "elm/core"},
        declaration_index: %{record_fields: ["pageIndex", "count"]},
        limit: 10
      })

    labels = Enum.map(suggestions, & &1.label)
    assert labels == ["count", "pageIndex"]
  end

  test "init context completions use launch context fields" do
    source = """
    module Main exposing (..)

    import Pebble.Platform as PebblePlatform

    type alias Model =
        { timeString : String
        , screenW : Int
        }

    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init context =
        context.
    """

    index = Ide.EditorCompletionDeclarationIndex.build(source)
    offset = String.length(source)

    launch_context_doc = %{
      "name" => "LaunchContext",
      "type" =>
        "{ reason : LaunchReason, watchModel : String, watchProfileId : String, screen : LaunchScreen, hasMicrophone : Bool, hasCompass : Bool, supportsHealth : Bool }"
    }

    launch_screen_doc = %{
      "name" => "LaunchScreen",
      "type" => "{ width : Int, height : Int, shape : DisplayShape, colorMode : ColorCapability }"
    }

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :record_field_access,
        qualifier: "context",
        declaration_index: index,
        source: source,
        cursor_offset: offset,
        editor_doc_packages: [
          %{
            package: "elm-pebble/elm-watch",
            docs: [
              %{
                "name" => "Pebble.Platform",
                "aliases" => [launch_context_doc, launch_screen_doc],
                "values" => [],
                "unions" => []
              }
            ]
          }
        ],
        limit: 50
      })

    labels = Enum.map(suggestions, & &1.label)

    assert "reason" in labels
    assert "screen" in labels
    assert "watchModel" in labels
    refute "timeString" in labels
    refute "screenW" in labels
  end

  test "contextual qualifier without package docs does not fall back to unrelated fields" do
    source = """
    module Main exposing (..)

    import Pebble.Platform as PebblePlatform

    type alias Model =
        { timeString : String }

    init : PebblePlatform.LaunchContext -> Model
    init context =
        context.
    """

    index = Ide.EditorCompletionDeclarationIndex.build(source)
    offset = String.length(source)

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :record_field_access,
        qualifier: "context",
        declaration_index: index,
        source: source,
        cursor_offset: offset,
        limit: 20
      })

    assert suggestions == []
  end

  test "update model completions use model fields" do
    source = """
    module Main exposing (..)

    type alias Model =
        { timeString : String
        , screenW : Int
        }

    type Msg
        = Tick

    update : Msg -> Model -> Model
    update msg model =
        model.
    """

    index = Ide.EditorCompletionDeclarationIndex.build(source)
    offset = String.length(source)

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :record_field_access,
        qualifier: "model",
        declaration_index: index,
        source: source,
        cursor_offset: offset,
        limit: 20
      })

    labels = Enum.map(suggestions, & &1.label)
    assert labels == ["screenW", "timeString"]
  end

  test "nested context screen completions use launch screen fields" do
    source = """
    module Main exposing (..)

    import Pebble.Platform as PebblePlatform

    init : PebblePlatform.LaunchContext -> Model
    init context =
        context.screen.
    """

    index = Ide.EditorCompletionDeclarationIndex.build(source)
    offset = String.length(source)

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :record_field_access,
        qualifier: "context.screen",
        declaration_index: index,
        source: source,
        cursor_offset: offset,
        editor_doc_packages: [
          %{
            package: "elm-pebble/elm-watch",
            docs: [
              %{
                "name" => "Pebble.Platform",
                "aliases" => [
                  %{
                    "name" => "LaunchContext",
                    "type" => "{ screen : LaunchScreen }"
                  },
                  %{
                    "name" => "LaunchScreen",
                    "type" => "{ width : Int, height : Int, shape : DisplayShape, colorMode : ColorCapability }"
                  }
                ],
                "values" => [],
                "unions" => []
              }
            ]
          }
        ],
        limit: 20
      })

    labels = Enum.map(suggestions, & &1.label)
    assert labels == ["colorMode", "height", "shape", "width"]
  end

  test "type annotation completions are limited to type names" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "I",
        context_kind: :type_annotation,
        parser_payload: %{
          metadata: %{module_exposing: ["update"], imports: [], import_entries: []}
        },
        token_tokens: [%{class: "identifier", text: "ignoredValue"}],
        package_doc_index: %{"Ignored.Package" => "elm/example"},
        declaration_index: %{types: ["Int", "IgnoredType"], values: ["ignoredValue"]},
        limit: 10
      })

    labels = Enum.map(suggestions, & &1.label)
    assert labels == ["IgnoredType", "Int"]
    refute "ignoredValue" in labels
    refute "import" in labels
  end

  test "qualified module completions use module docs and not record fields" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "",
        context_kind: :module_qualified_access,
        qualifier: "List",
        declaration_index: %{record_fields: ["pageIndex"]},
        editor_doc_packages: [
          %{
            package: "elm/core",
            docs: [
              %{
                "name" => "List",
                "values" => [
                  %{"name" => "map"},
                  %{"name" => "filter"}
                ],
                "aliases" => [],
                "unions" => []
              }
            ]
          }
        ],
        limit: 50
      })

    labels = Enum.map(suggestions, & &1.label)
    assert "filter" in labels
    assert "map" in labels
    refute "pageIndex" in labels
  end

  test "qualified module completions resolve import aliases" do
    {:ok, docs} = Ide.Packages.builtin_package_docs("elm-pebble/elm-watch")

    index =
      Ide.EditorCompletionDeclarationIndex.build("""
      module Main exposing (main)

      import Pebble.Events as PebbleEvents
      """)

    suggestions =
      EditorCompletion.suggest(%{
        prefix: "on",
        context_kind: :module_qualified_access,
        qualifier: "PebbleEvents",
        declaration_index: index,
        editor_doc_packages: [%{package: "elm-pebble/elm-watch", docs: docs}],
        limit: 50
      })

    labels = Enum.map(suggestions, & &1.label)
    assert "onDayChange" in labels
    assert "onHourChange" in labels
    assert "onMinuteChange" in labels
    refute "HourChanged" in labels
    refute "MinuteChanged" in labels
  end

  test "value expression completions include values and constructors" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: "N",
        context_kind: :value_expression,
        declaration_index: %{values: ["nextPage"], constructors: ["Next"]},
        limit: 10
      })

    labels = Enum.map(suggestions, & &1.label)
    assert "Next" in labels
    assert "nextPage" in labels
  end

  test "keeps field accessor dot outside field access context" do
    suggestions =
      EditorCompletion.suggest(%{
        prefix: ".p",
        context_kind: :value_expression,
        token_tokens: [%{class: "field_identifier", text: ".pageIndex"}],
        limit: 10
      })

    assert [%{label: ".pageIndex", insert_text: ".pageIndex"}] = suggestions
  end
end
