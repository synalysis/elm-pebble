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
end
