defmodule Ide.EditorCompletionContext do
  @moduledoc """
  Classifies the syntactic completion context at a cursor offset.
  """

  alias Ide.EditorCompletionDeclarationIndex

  @identifier_suffix ~r/([A-Za-z_][A-Za-z0-9_']*)$/

  @type kind ::
          :record_field_access
          | :module_qualified_access
          | :type_annotation
          | :value_expression
          | :unknown

  @type t :: %{
          kind: kind(),
          prefix: String.t(),
          qualifier: String.t() | nil,
          replace_from: non_neg_integer(),
          replace_to: non_neg_integer(),
          offset: non_neg_integer(),
          source: String.t(),
          declaration_index: EditorCompletionDeclarationIndex.t()
        }

  @spec analyze(map()) :: t()
  def analyze(%{source: source, offset: offset} = opts)
      when is_binary(source) and is_integer(offset) do
    safe_offset = min(max(offset, 0), String.length(source))
    prefix = completion_prefix(String.slice(source, 0, safe_offset))
    replace_from = safe_offset - String.length(prefix)
    declaration_index = opts[:declaration_index] || EditorCompletionDeclarationIndex.build(source)
    {kind, qualifier} = classify(source, replace_from)

    %{
      kind: kind,
      prefix: prefix,
      qualifier: qualifier,
      replace_from: replace_from,
      replace_to: safe_offset,
      offset: safe_offset,
      source: source,
      declaration_index: declaration_index
    }
  end

  def analyze(_opts) do
    %{
      kind: :unknown,
      prefix: "",
      qualifier: nil,
      replace_from: 0,
      replace_to: 0,
      offset: 0,
      source: "",
      declaration_index: EditorCompletionDeclarationIndex.empty()
    }
  end

  @spec completion_prefix(String.t()) :: String.t()
  def completion_prefix(prefix_text) when is_binary(prefix_text) do
    case Regex.run(@identifier_suffix, prefix_text) do
      [_, prefix] -> prefix
      _ -> ""
    end
  end

  defp classify(source, replace_from) do
    cond do
      module_qualified_access_position?(source, replace_from) ->
        {:module_qualified_access, qualifier_before_dot(source, replace_from)}

      record_field_access_position?(source, replace_from) ->
        {:record_field_access, qualifier_before_dot(source, replace_from)}

      type_annotation_position?(source, replace_from) ->
        {:type_annotation, nil}

      true ->
        {:value_expression, nil}
    end
  end

  defp module_qualified_access_position?(source, offset) do
    case qualifier_before_dot(source, offset) do
      <<first::utf8, _::binary>> -> first in ?A..?Z
      _ -> false
    end
  end

  defp record_field_access_position?(source, offset) do
    safe_offset = min(max(offset, 0), String.length(source))
    safe_offset > 0 && String.at(source, safe_offset - 1) == "."
  end

  defp qualifier_before_dot(source, offset) do
    safe_offset = min(max(offset, 0), String.length(source))
    prefix = String.slice(source, 0, safe_offset)

    case Regex.run(~r/([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*)\.$/, prefix) do
      [_, qualifier] -> qualifier
      _ -> nil
    end
  end

  defp type_annotation_position?(source, offset) do
    {line, column} = line_and_column(source, offset)
    before_cursor = String.slice(line, 0, column)

    case String.split(before_cursor, ":", parts: 2) do
      [_before_colon, after_colon] ->
        not String.contains?(after_colon, "=")

      _ ->
        false
    end
  end

  defp line_and_column(source, offset) do
    safe_offset = min(max(offset, 0), String.length(source))
    prefix = String.slice(source, 0, safe_offset)

    case String.split(prefix, "\n", trim: false) do
      [] ->
        {"", 0}

      lines ->
        line = List.last(lines) || ""
        {line, String.length(line)}
    end
  end
end
