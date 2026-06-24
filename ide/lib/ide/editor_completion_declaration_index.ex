defmodule Ide.EditorCompletionDeclarationIndex do
  @moduledoc """
  Lightweight declaration index for syntax-aware editor completions.
  """

  alias Ide.EditorCompletionTypeParse

  @builtin_types ~w(
    Bool Char Cmd Dict Float Int List Maybe Never Order Platform.Program Result String Sub
  )

  @type contract_declaration :: %{
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type function_scope :: %{
          required(:name) => String.t(),
          required(:start_line) => non_neg_integer(),
          required(:end_line) => non_neg_integer(),
          required(:bindings) => %{optional(String.t()) => String.t()}
        }

  @type t :: %{
          types: [String.t()],
          values: [String.t()],
          constructors: [String.t()],
          record_fields: [String.t()],
          record_fields_by_type: %{String.t() => [String.t()]},
          field_types_by_type: %{String.t() => %{String.t() => String.t()}},
          function_scopes: [function_scope()],
          import_aliases: %{String.t() => String.t()}
        }

  @spec empty() :: t()
  def empty do
    %{
      types: @builtin_types,
      values: [],
      constructors: [],
      record_fields: [],
      record_fields_by_type: %{},
      field_types_by_type: %{},
      function_scopes: [],
      import_aliases: %{}
    }
  end

  @spec build(String.t()) :: t()
  def build(source) when is_binary(source) do
    module_name = module_name(source) || "Main"

    with {:module, ElmEx.Frontend.GeneratedContractBuilder} <-
           Code.ensure_loaded(ElmEx.Frontend.GeneratedContractBuilder) do
      declarations =
        "Main.elm"
        |> ElmEx.Frontend.GeneratedContractBuilder.build(source, module_name, [])
        |> Map.get(:declarations, [])

      source
      |> from_declarations(declarations)
      |> Map.put(:import_aliases, parse_import_aliases(source))
    else
      _ ->
        empty() |> Map.put(:import_aliases, parse_import_aliases(source))
    end
  rescue
    _ ->
      empty() |> Map.put(:import_aliases, parse_import_aliases(source))
  end

  @spec from_declarations([contract_declaration()]) :: t()
  def from_declarations(declarations) when is_list(declarations) do
    from_declarations("", declarations)
  end

  @spec from_declarations(String.t(), [contract_declaration()]) :: t()
  def from_declarations(source, declarations) when is_binary(source) and is_list(declarations) do
    index =
      Enum.reduce(declarations, empty(), fn declaration, acc ->
        case declaration_kind(declaration) do
          :type_alias ->
            name = declaration_value(declaration, :name)
            fields = declaration_value(declaration, :fields) |> List.wrap()
            field_types = declaration_value(declaration, :field_types) |> normalize_field_types()

            acc
            |> add_unique(:types, name)
            |> add_many_unique(:record_fields, fields)
            |> put_type_maps(name, fields, field_types)

          :union ->
            name = declaration_value(declaration, :name)
            constructors = declaration_value(declaration, :constructors) |> List.wrap()

            acc
            |> add_unique(:types, name)
            |> add_many_unique(:constructors, Enum.map(constructors, &constructor_name/1))

          kind when kind in [:function_definition, :function_signature] ->
            add_unique(acc, :values, declaration_value(declaration, :name))

          _ ->
            acc
        end
      end)

  index
  |> Map.put(:function_scopes, function_scopes_from_declarations(declarations))
  |> sort_index()
  end

  def from_declarations(_source, _), do: empty()

  @spec parse_import_aliases(String.t()) :: %{String.t() => String.t()}
  def parse_import_aliases(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.reduce(%{}, fn line, acc ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "import ") ->
          parse_import_line(trimmed, acc)

        true ->
          acc
      end
    end)
  end

  def parse_import_aliases(_), do: %{}

  defp parse_import_line(line, acc) do
    trimmed = String.trim(line)

    with [_, module] <- Regex.run(~r/^import\s+([A-Z][A-Za-z0-9_.']*)/, trimmed) do
      alias_name =
        case Regex.run(~r/\s+as\s+([A-Za-z_][A-Za-z0-9_']*)/, trimmed) do
          [_, alias] -> strip_exposing_suffix(alias)
          _ -> module |> String.split(".") |> List.last()
        end

      Map.put(acc, alias_name, module)
    else
      _ -> acc
    end
  end

  defp strip_exposing_suffix(name) when is_binary(name) do
    case Regex.run(~r/^(.*?)(?:exposing|eposing|xposing|posing)$/u, name) do
      [_, base] when byte_size(base) > 0 -> base
      _ -> name
    end
  end

  defp function_scopes_from_declarations(declarations) do
    signatures =
      declarations
      |> Enum.filter(&(declaration_kind(&1) == :function_signature))
      |> Map.new(fn decl ->
        {declaration_value(decl, :name), declaration_value(decl, :type)}
      end)

    declarations
    |> Enum.filter(&(declaration_kind(&1) == :function_definition))
    |> Enum.map(fn decl ->
      name = declaration_value(decl, :name)
      args = declaration_value(decl, :args) |> List.wrap() |> Enum.map(&to_string/1)
      span = declaration_value(decl, :span) || %{}
      param_types = signatures |> Map.get(name, "") |> EditorCompletionTypeParse.function_param_types()
      bindings = zip_param_bindings(args, param_types)

      %{
        name: name,
        start_line: Map.get(span, :start_line) || Map.get(span, "start_line") || 0,
        end_line: Map.get(span, :end_line) || Map.get(span, "end_line") || 0,
        bindings: bindings
      }
    end)
    |> Enum.sort_by(& &1.start_line)
  end

  defp zip_param_bindings(args, param_types) do
    args
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {arg, index}, acc ->
      type = Enum.at(param_types, index)

      if is_binary(type) and type != "" do
        Map.put(acc, arg, String.trim(type))
      else
        acc
      end
    end)
  end

  defp put_type_maps(acc, type_name, fields, field_types) when is_binary(type_name) do
    acc
    |> Map.update!(:record_fields_by_type, fn by_type ->
      Map.put(by_type, type_name, Enum.map(fields, &to_string/1))
    end)
    |> Map.update!(:field_types_by_type, fn by_type ->
      Map.put(by_type, type_name, field_types)
    end)
  end

  defp put_type_maps(acc, _type_name, _fields, _field_types), do: acc

  defp normalize_field_types(field_types) when is_map(field_types) do
    Map.new(field_types, fn {name, type} -> {to_string(name), to_string(type || "")} end)
  end

  defp normalize_field_types(_), do: %{}

  defp module_name(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.find_value(&parse_module_name_from_line/1)
  end

  defp parse_module_name_from_line(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "module ") ->
        trimmed |> String.slice(7, String.length(trimmed)) |> take_upper_path()

      String.starts_with?(trimmed, "effect module ") ->
        trimmed |> String.slice(14, String.length(trimmed)) |> take_upper_path()

      String.starts_with?(trimmed, "port module ") ->
        trimmed |> String.slice(12, String.length(trimmed)) |> take_upper_path()

      true ->
        nil
    end
  end

  defp take_upper_path(value) when is_binary(value) do
    case Regex.run(~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*/, value) do
      [module_name | _] -> module_name
      _ -> nil
    end
  end

  defp declaration_kind(declaration), do: declaration_value(declaration, :kind)

  defp declaration_value(declaration, key) when is_map(declaration) do
    Map.get(declaration, key) || Map.get(declaration, Atom.to_string(key))
  end

  defp declaration_value(_, _), do: nil

  defp constructor_name(%{name: name}), do: name
  defp constructor_name(%{"name" => name}), do: name
  defp constructor_name(name) when is_binary(name), do: name
  defp constructor_name(_), do: nil

  defp add_many_unique(acc, key, values) do
    Enum.reduce(values, acc, &add_unique(&2, key, &1))
  end

  defp add_unique(acc, _key, value) when not is_binary(value), do: acc
  defp add_unique(acc, _key, ""), do: acc

  defp add_unique(acc, key, value) do
    Map.update!(acc, key, fn values ->
      if value in values, do: values, else: [value | values]
    end)
  end

  defp sort_index(index) do
    index
    |> Map.new(fn
      {key, values} when is_list(values) -> {key, Enum.sort(values)}
      {key, values} -> {key, values}
    end)
  end
end
