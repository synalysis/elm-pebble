defmodule Ide.Diagnostics.ElmSyntaxCatalogTest do
  use ExUnit.Case, async: true

  alias Ide.Diagnostics.ElmSyntaxCatalog
  alias Ide.Diagnostics.TokenizerParserMapper

  test "catalog tracks full Syntax.hs title inventory" do
    titles = ElmSyntaxCatalog.all_titles()
    matrix = ElmSyntaxCatalog.coverage_matrix()

    assert length(titles) >= 84
    assert length(matrix) == length(titles)
    assert Enum.all?(matrix, &is_atom(&1.catalog_id))
    assert Enum.all?(matrix, &(&1.mapper_entrypoint == "from_title/6"))
  end

  test "all declared catalog ids resolve to entries" do
    assert Enum.all?(ElmSyntaxCatalog.all_ids(), &(ElmSyntaxCatalog.entry(&1) != nil))
  end

  test "mapper routes explicit Elm titles through catalog metadata" do
    diagnostic =
      TokenizerParserMapper.from_title(
        "PROBLEM IN CUSTOM TYPE",
        "warning",
        "tokenizer/decl_parser",
        4,
        7,
        detail: "Constructor starts with a number."
      )

    assert diagnostic.catalog_id == :problem_in_custom_type
    assert diagnostic.elm_title == "PROBLEM IN CUSTOM TYPE"
    assert String.contains?(diagnostic.message, "PROBLEM IN CUSTOM TYPE")
  end
end
