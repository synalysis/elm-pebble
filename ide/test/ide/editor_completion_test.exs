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
