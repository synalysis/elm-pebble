defmodule Ide.EditorCompletionDeclarationIndex do
  @moduledoc """
  Lightweight declaration index for syntax-aware editor completions.
  """

  @builtin_types ~w(
    Bool Char Cmd Dict Float Int List Maybe Never Order Platform.Program Result String Sub
  )

  @type t :: %{
          types: [String.t()],
          values: [String.t()],
          constructors: [String.t()],
          record_fields: [String.t()]
        }

  @spec empty() :: t()
  def empty do
    %{types: @builtin_types, values: [], constructors: [], record_fields: []}
  end

  @spec build(String.t()) :: t()
  def build(source) when is_binary(source) do
    module_name = module_name(source) || "Main"

    with {:module, ElmEx.Frontend.GeneratedContractBuilder} <-
           Code.ensure_loaded(ElmEx.Frontend.GeneratedContractBuilder) do
      "Main.elm"
      |> ElmEx.Frontend.GeneratedContractBuilder.build(source, module_name, [])
      |> Map.get(:declarations, [])
      |> from_declarations()
    else
      _ -> empty()
    end
  rescue
    _ -> empty()
  end

  @spec from_declarations([map()]) :: t()
  def from_declarations(declarations) when is_list(declarations) do
    Enum.reduce(declarations, empty(), fn declaration, acc ->
      case declaration_kind(declaration) do
        :type_alias ->
          name = declaration_value(declaration, :name)
          fields = declaration_value(declaration, :fields) |> List.wrap()

          acc
          |> add_unique(:types, name)
          |> add_many_unique(:record_fields, fields)

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
    |> sort_index()
  end

  def from_declarations(_), do: empty()

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
    Map.new(index, fn {key, values} -> {key, Enum.sort(values)} end)
  end
end
