defmodule Ide.EditorCompletion do
  @moduledoc """
  Aggregates completion candidates from parser/token context and workspace package knowledge.
  """

  @default_limit 24

  @keywords ~w(
    module import exposing type alias let in case of if then else port where as
  )

  @token_symbol_classes ~w(identifier type_identifier field_identifier)

  @type suggestion :: %{
          label: String.t(),
          insert_text: String.t(),
          kind: String.t(),
          source: String.t()
        }

  @type context :: %{
          optional(:prefix) => String.t() | nil,
          optional(:parser_payload) => map() | nil,
          optional(:token_tokens) => [map()],
          optional(:package_doc_index) => map(),
          optional(:editor_doc_packages) => [map()],
          optional(:direct_dependencies) => [map()],
          optional(:indirect_dependencies) => [map()],
          optional(:limit) => pos_integer()
        }

  @spec suggest(context()) :: [suggestion()]
  def suggest(context) when is_map(context) do
    prefix = context[:prefix] || ""
    lowered_prefix = String.downcase(prefix)
    limit = context[:limit] || @default_limit

    candidates =
      keyword_candidates()
      |> Kernel.++(parser_candidates(context[:parser_payload]))
      |> Kernel.++(token_candidates(context[:token_tokens]))
      |> Kernel.++(package_module_candidates(context[:package_doc_index]))
      |> Kernel.++(editor_doc_module_candidates(context[:editor_doc_packages]))
      |> Kernel.++(dependency_candidates(context[:direct_dependencies], "dependency/direct"))
      |> Kernel.++(dependency_candidates(context[:indirect_dependencies], "dependency/indirect"))
      |> Enum.filter(&valid_candidate?/1)
      |> Enum.uniq_by(&String.downcase(&1.label))

    candidates
    |> Enum.filter(&matches_prefix?(&1.label, lowered_prefix))
    |> Enum.sort_by(&candidate_sort_key(&1, lowered_prefix))
    |> Enum.take(limit)
    |> Enum.map(fn row ->
      %{
        label: row.label,
        insert_text: row.insert_text || row.label,
        kind: row.kind,
        source: row.source
      }
    end)
  end

  @spec keyword_candidates() :: term()
  defp keyword_candidates do
    Enum.map(@keywords, fn kw ->
      %{label: kw, insert_text: kw, kind: "keyword", source: "language/keyword"}
    end)
  end

  @spec parser_candidates(term()) :: term()
  defp parser_candidates(%{metadata: metadata}) when is_map(metadata) do
    imports = List.wrap(metadata[:imports])
    ports = List.wrap(metadata[:ports])
    module_name = metadata[:module]

    exposing_items =
      case metadata[:module_exposing] do
        list when is_list(list) -> list
        ".." -> []
        _ -> []
      end

    import_entries =
      metadata[:import_entries]
      |> List.wrap()
      |> Enum.flat_map(fn row ->
        module_name = row["module"] || row[:module]
        alias_name = row["as"] || row[:as]
        exposing = row["exposing"] || row[:exposing]
        exposing_list = if is_list(exposing), do: exposing, else: []
        [module_name, alias_name | exposing_list]
      end)

    parser_symbols =
      [module_name | imports] ++ ports ++ exposing_items ++ import_entries

    Enum.map(parser_symbols, fn symbol ->
      %{
        label: to_string(symbol || ""),
        insert_text: to_string(symbol || ""),
        kind: "symbol",
        source: "parser"
      }
    end)
  end

  defp parser_candidates(_), do: []

  @spec token_candidates(term()) :: term()
  defp token_candidates(tokens) when is_list(tokens) do
    tokens
    |> Enum.flat_map(fn token ->
      text = token[:text] || token["text"]
      klass = token[:class] || token["class"]

      if klass in @token_symbol_classes and is_binary(text) and text != "" do
        [%{label: text, insert_text: text, kind: "symbol", source: "tokenizer"}]
      else
        []
      end
    end)
  end

  defp token_candidates(_), do: []

  @spec package_module_candidates(term()) :: term()
  defp package_module_candidates(index) when is_map(index) do
    Enum.map(index, fn {module_name, _package} ->
      %{
        label: to_string(module_name),
        insert_text: to_string(module_name),
        kind: "module",
        source: "packages/index"
      }
    end)
  end

  defp package_module_candidates(_), do: []

  @spec editor_doc_module_candidates(term()) :: term()
  defp editor_doc_module_candidates(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn row ->
      modules = row[:modules] || row["modules"] || []

      Enum.map(List.wrap(modules), fn module_name ->
        %{
          label: to_string(module_name),
          insert_text: to_string(module_name),
          kind: "module",
          source: "packages/docs"
        }
      end)
    end)
  end

  defp editor_doc_module_candidates(_), do: []

  @spec dependency_candidates(term(), term()) :: term()
  defp dependency_candidates(rows, source) when is_list(rows) and is_binary(source) do
    Enum.map(rows, fn row ->
      name = row[:name] || row["name"] || ""
      %{label: to_string(name), insert_text: to_string(name), kind: "package", source: source}
    end)
  end

  defp dependency_candidates(_, _), do: []

  @spec valid_candidate?(term()) :: term()
  defp valid_candidate?(%{label: label}) when is_binary(label), do: String.trim(label) != ""
  defp valid_candidate?(_), do: false

  @spec matches_prefix?(term(), term()) :: term()
  defp matches_prefix?(_value, ""), do: true

  defp matches_prefix?(value, lowered_prefix)
       when is_binary(value) and is_binary(lowered_prefix) do
    String.starts_with?(String.downcase(value), lowered_prefix)
  end

  @spec candidate_sort_key(term(), term()) :: term()
  defp candidate_sort_key(candidate, lowered_prefix) do
    value = String.downcase(candidate.label)

    prefix_score =
      cond do
        lowered_prefix == "" -> 2
        value == lowered_prefix -> 0
        String.starts_with?(value, lowered_prefix) -> 1
        true -> 3
      end

    source_score =
      case candidate.source do
        "parser" -> 0
        "tokenizer" -> 1
        "language/keyword" -> 2
        "packages/index" -> 3
        "packages/docs" -> 4
        "dependency/direct" -> 5
        "dependency/indirect" -> 6
        _ -> 7
      end

    {prefix_score, source_score, value}
  end
end
