defmodule Ide.EditorCompletion do
  @moduledoc """
  Aggregates completion candidates from parser/token context and workspace package knowledge.
  """

  @default_limit 24

  @keywords ~w(
    module import exposing type alias let in case of if then else port where as
  )

  @core_module_members %{
    "List" => ~w(
      all any append concat concatMap drop filter filterMap foldl foldr head indexedMap
      isEmpty length map map2 map3 map4 map5 member partition range repeat reverse
      singleton sort sortBy sortWith sum tail take unzip
    ),
    "Maybe" => ~w(andThen map map2 map3 map4 map5 withDefault),
    "Result" => ~w(andThen fromMaybe map map2 map3 map4 map5 mapError toMaybe withDefault),
    "String" => ~w(
      all any append concat contains dropLeft dropRight endsWith filter foldl foldr fromChar
      fromFloat fromInt indexes isEmpty join length lines map pad padLeft padRight repeat
      replace reverse slice split startsWith toFloat toInt toList toLower toUpper trim
      trimLeft trimRight uncons words
    )
  }

  @token_symbol_classes ~w(identifier type_identifier field_identifier)

  @type candidate_row :: %{
          label: String.t(),
          insert_text: String.t(),
          kind: String.t(),
          source: String.t()
        }

  @type suggestion :: candidate_row()
  @type candidate_list :: [candidate_row()]

  @type context :: %{
          optional(:prefix) => String.t() | nil,
          optional(:parser_payload) => map() | nil,
          optional(:token_tokens) => [map()],
          optional(:package_doc_index) => map(),
          optional(:editor_doc_packages) => [map()],
          optional(:direct_dependencies) => [map()],
          optional(:indirect_dependencies) => [map()],
          optional(:record_fields) => [String.t()],
          optional(:context_kind) => atom(),
          optional(:qualifier) => String.t() | nil,
          optional(:declaration_index) => map(),
          optional(:limit) => pos_integer()
        }

  @spec suggest(context()) :: [suggestion()]
  def suggest(context) when is_map(context) do
    prefix = context[:prefix] || ""
    lowered_prefix = String.downcase(prefix)
    context_kind = completion_context_kind(context)
    field_access? = context_kind == :record_field_access
    limit = context[:limit] || @default_limit

    candidates =
      context
      |> candidates(context_kind)
      |> Enum.filter(&valid_candidate?/1)
      |> Enum.uniq_by(&String.downcase(&1.label))

    candidates
    |> Enum.filter(&matches_prefix?(&1.label, lowered_prefix, field_access?))
    |> Enum.sort_by(&candidate_sort_key(&1, lowered_prefix, field_access?))
    |> Enum.take(limit)
    |> Enum.map(fn row ->
      %{
        label: row.label,
        insert_text: insert_text(row, field_access?),
        kind: row.kind,
        source: row.source
      }
    end)
  end

  @spec keyword_candidates() :: candidate_list()
  defp keyword_candidates do
    Enum.map(@keywords, fn kw ->
      %{label: kw, insert_text: kw, kind: "keyword", source: "language/keyword"}
    end)
  end

  @spec parser_candidates(map() | nil) :: candidate_list()
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

  @spec token_candidates([map()] | nil) :: candidate_list()
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

  @spec field_candidates(map()) :: candidate_list()
  defp field_candidates(context) when is_map(context) do
    fields =
      case declaration_index_values(context, :record_fields) do
        [] -> context[:record_fields]
        values -> values
      end

    record_field_candidates(fields)
  end

  @spec record_field_candidates([String.t()] | nil) :: candidate_list()
  defp record_field_candidates(fields) when is_list(fields) do
    fields
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.map(fn field ->
      %{label: field, insert_text: field, kind: "field", source: "record/type-alias"}
    end)
  end

  defp record_field_candidates(_), do: []

  @spec type_candidates(map()) :: candidate_list()
  defp type_candidates(context) when is_map(context) do
    context
    |> declaration_index_values(:types)
    |> Enum.map(fn type_name ->
      %{label: type_name, insert_text: type_name, kind: "type", source: "declaration/type"}
    end)
  end

  @spec declaration_value_candidates(map()) :: candidate_list()
  defp declaration_value_candidates(context) when is_map(context) do
    values =
      context
      |> declaration_index_values(:values)
      |> Enum.map(fn value_name ->
        %{label: value_name, insert_text: value_name, kind: "symbol", source: "declaration/value"}
      end)

    constructors =
      context
      |> declaration_index_values(:constructors)
      |> Enum.map(fn constructor_name ->
        %{
          label: constructor_name,
          insert_text: constructor_name,
          kind: "constructor",
          source: "declaration/constructor"
        }
      end)

    values ++ constructors
  end

  @spec package_module_candidates(map() | nil) :: candidate_list()
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

  @spec editor_doc_module_candidates([map()] | nil) :: candidate_list()
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

  @spec module_member_candidates(map()) :: candidate_list()
  defp module_member_candidates(context) when is_map(context) do
    qualifier = context[:qualifier]

    doc_members =
      context[:editor_doc_packages]
      |> List.wrap()
      |> Enum.flat_map(&module_members_from_package(&1, qualifier))

    doc_members ++ core_module_member_candidates(qualifier)
  end

  defp module_members_from_package(package_row, qualifier) when is_map(package_row) do
    package = package_row[:package] || package_row["package"] || "package"

    package_row
    |> module_docs()
    |> Enum.filter(fn module_doc -> module_name(module_doc) == qualifier end)
    |> Enum.flat_map(&module_doc_members(&1, package))
  end

  defp module_members_from_package(_package_row, _qualifier), do: []

  defp core_module_member_candidates(qualifier) do
    @core_module_members
    |> Map.get(qualifier, [])
    |> Enum.map(fn member ->
      %{label: member, insert_text: member, kind: "function", source: "elm/core"}
    end)
  end

  defp module_docs(package_row) do
    package_row[:docs] || package_row["docs"] || package_row[:modules] || package_row["modules"] ||
      []
  end

  defp module_name(module_doc) when is_map(module_doc),
    do: module_doc[:name] || module_doc["name"]

  defp module_name(_module_doc), do: nil

  defp module_doc_members(module_doc, package) when is_map(module_doc) do
    module_doc_values(module_doc, "values", "function", package) ++
      module_doc_values(module_doc, "aliases", "type", package) ++
      module_doc_values(module_doc, "unions", "type", package) ++
      module_doc_union_constructors(module_doc, package)
  end

  defp module_doc_members(_module_doc, _package), do: []

  defp module_doc_values(module_doc, key, kind, package) do
    module_doc
    |> Map.get(key, Map.get(module_doc, String.to_atom(key), []))
    |> List.wrap()
    |> Enum.flat_map(fn row ->
      name = row[:name] || row["name"]

      if is_binary(name) and name != "" do
        [%{label: name, insert_text: name, kind: kind, source: "docs/#{package}"}]
      else
        []
      end
    end)
  end

  defp module_doc_union_constructors(module_doc, package) do
    module_doc
    |> Map.get("unions", Map.get(module_doc, :unions, []))
    |> List.wrap()
    |> Enum.flat_map(fn union ->
      union
      |> Map.get("cases", Map.get(union, :cases, []))
      |> List.wrap()
      |> Enum.flat_map(fn
        [name | _] when is_binary(name) ->
          [%{label: name, insert_text: name, kind: "constructor", source: "docs/#{package}"}]

        %{name: name} when is_binary(name) ->
          [%{label: name, insert_text: name, kind: "constructor", source: "docs/#{package}"}]

        %{"name" => name} when is_binary(name) ->
          [%{label: name, insert_text: name, kind: "constructor", source: "docs/#{package}"}]

        _ ->
          []
      end)
    end)
  end

  @spec dependency_candidates([map()] | nil, String.t()) :: candidate_list()
  defp dependency_candidates(rows, source) when is_list(rows) and is_binary(source) do
    Enum.map(rows, fn row ->
      name = row[:name] || row["name"] || ""
      %{label: to_string(name), insert_text: to_string(name), kind: "package", source: source}
    end)
  end

  defp dependency_candidates(_, _), do: []

  @spec candidates(map(), atom()) :: candidate_list()
  defp candidates(context, :record_field_access), do: field_candidates(context)
  defp candidates(context, :module_qualified_access), do: module_member_candidates(context)
  defp candidates(context, :type_annotation), do: type_candidates(context)

  defp candidates(context, :value_expression) do
    keyword_candidates()
    |> Kernel.++(declaration_value_candidates(context))
    |> Kernel.++(parser_candidates(context[:parser_payload]))
    |> Kernel.++(token_candidates(context[:token_tokens]))
    |> Kernel.++(package_module_candidates(context[:package_doc_index]))
    |> Kernel.++(editor_doc_module_candidates(context[:editor_doc_packages]))
    |> Kernel.++(dependency_candidates(context[:direct_dependencies], "dependency/direct"))
    |> Kernel.++(dependency_candidates(context[:indirect_dependencies], "dependency/indirect"))
  end

  defp candidates(context, _unknown), do: candidates(context, :value_expression)

  @spec completion_context_kind(map()) :: atom()
  defp completion_context_kind(%{context_kind: kind}) when is_atom(kind), do: kind
  defp completion_context_kind(_context), do: :value_expression

  @spec declaration_index_values(map(), atom()) :: [String.t()]
  defp declaration_index_values(context, key) when is_map(context) do
    index = context[:declaration_index] || %{}
    Map.get(index, key) || Map.get(index, Atom.to_string(key)) || []
  end

  @spec valid_candidate?(candidate_row()) :: boolean()
  defp valid_candidate?(%{label: label}) when is_binary(label), do: String.trim(label) != ""
  defp valid_candidate?(_), do: false

  @spec matches_prefix?(String.t(), String.t(), boolean()) :: boolean()
  defp matches_prefix?(_value, "", _field_access?), do: true

  defp matches_prefix?(value, lowered_prefix, field_access?)
       when is_binary(value) and is_binary(lowered_prefix) do
    lowered_value = String.downcase(value)

    String.starts_with?(lowered_value, lowered_prefix) ||
      (field_access? &&
         String.starts_with?(String.trim_leading(lowered_value, "."), lowered_prefix))
  end

  @spec candidate_sort_key(candidate_row(), String.t(), boolean()) ::
          {non_neg_integer(), non_neg_integer(), String.t()}
  defp candidate_sort_key(candidate, lowered_prefix, field_access?) do
    value =
      candidate.label
      |> String.downcase()
      |> maybe_trim_field_dot(field_access?)

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
        "record/type-alias" -> 0
        "declaration/type" -> 0
        "declaration/value" -> 0
        "declaration/constructor" -> 0
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

  @spec insert_text(candidate_row(), boolean()) :: String.t()
  defp insert_text(candidate, field_access?) do
    (candidate.insert_text || candidate.label)
    |> maybe_trim_field_dot(field_access?)
  end

  @spec maybe_trim_field_dot(String.t(), boolean()) :: String.t()
  defp maybe_trim_field_dot(value, true) when is_binary(value),
    do: String.trim_leading(value, ".")

  defp maybe_trim_field_dot(value, _field_access?) when is_binary(value), do: value
end
