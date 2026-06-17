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
    {kind, qualifier} = classify(source, safe_offset, prefix)

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

  defp classify(source, offset, prefix) do
    case field_access_context(source, offset, prefix) do
      {:ok, qualifier} ->
        root = qualifier |> String.split(".") |> List.first() || ""

        if String.match?(root, ~r/^[A-Z]/) do
          {:module_qualified_access, qualifier}
        else
          {:record_field_access, qualifier}
        end

      :error ->
        cond do
          type_annotation_position?(source, offset - String.length(prefix)) ->
            {:type_annotation, nil}

          true ->
            {:value_expression, nil}
        end
    end
  end

  defp field_access_context(source, offset, prefix) when is_binary(source) do
    safe_offset = min(max(offset, 0), String.length(source))
    replace_from = safe_offset - String.length(prefix)

    dot_index =
      if prefix != "" do
        if replace_from > 0 and String.at(source, replace_from - 1) == ".", do: replace_from - 1
      else
        scan_back_for_dot_index(source, safe_offset - 1)
      end

    with dot when is_integer(dot) and dot >= 0 <- dot_index,
         prefix_before_dot <- String.slice(source, 0, dot + 1),
         [_, qualifier] <-
           Regex.run(
             ~r/([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.$/,
             prefix_before_dot
           ) do
      {:ok, qualifier}
    else
      _ -> :error
    end
  end

  defp scan_back_for_dot_index(_source, pos) when pos < 0, do: nil

  defp scan_back_for_dot_index(source, pos) when is_binary(source) do
    case String.at(source, pos) do
      "." -> pos
      c when c in [" ", "\t", "\n", "\r"] -> scan_back_for_dot_index(source, pos - 1)
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
