defmodule Elmx.TeaPlaybook.Protocol do
  @moduledoc """
  Parses `protocol/src/Companion/Types.elm` `PhoneToWatch` for shared TEA playbooks.

  Constructor tags match elmc union macros (1-based). Argument types are split on
  top-level spaces so `(List Int)` counts as one argument.
  """

  @type phone_ctor :: %{
          name: String.t(),
          tag: pos_integer(),
          arity: non_neg_integer(),
          args: [String.t()]
        }

  @repo_root Path.expand("../../../..", __DIR__)

  @spec types_path(String.t()) :: String.t() | nil
  def types_path(template) when is_binary(template) do
    path =
      Path.join([
        @repo_root,
        "ide/priv/project_templates",
        template,
        "protocol/src/Companion/Types.elm"
      ])

    if File.regular?(path), do: path
  end

  @spec phone_to_watch_constructors(String.t()) :: [phone_ctor()]
  def phone_to_watch_constructors(template) when is_binary(template) do
    case types_path(template) do
      nil -> []
      path -> parse_phone_to_watch(File.read!(path))
    end
  end

  @spec phone_tag(String.t(), String.t()) :: pos_integer() | nil
  def phone_tag(template, ctor_name) when is_binary(template) and is_binary(ctor_name) do
    phone_to_watch_constructors(template)
    |> Enum.find_value(fn %{name: name, tag: tag} -> if name == ctor_name, do: tag end)
  end

  @spec parse_phone_to_watch(String.t()) :: [phone_ctor()]
  def parse_phone_to_watch(source) when is_binary(source) do
    case Regex.run(~r/type\s+PhoneToWatch\b([\s\S]*?)(?:\n\n|\z)/, source) do
      [_, block] ->
        block
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&parse_phone_line/1)
        |> Enum.with_index(1)
        |> Enum.map(fn {ctor, tag} -> Map.put(ctor, :tag, tag) end)

      _ ->
        []
    end
  end

  defp parse_phone_line(line) do
    line =
      line
      |> String.trim()
      |> String.replace_prefix("=", "")
      |> String.trim_leading("|")
      |> String.trim()

    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_]*)\s*(.*)$/, line) do
      [_, name, rest] ->
        args = split_type_tokens(rest)
        [%{name: name, arity: length(args), args: args}]

      _ ->
        []
    end
  end

  @doc false
  @spec split_type_tokens(String.t()) :: [String.t()]
  def split_type_tokens(line) when is_binary(line) do
    split_type_tokens(String.trim(line), 0, false, "", [])
    |> Enum.reverse()
  end

  defp split_type_tokens("", _depth, _in_parens, current, acc) do
    case String.trim(current) do
      "" -> acc
      token -> [token | acc]
    end
  end

  defp split_type_tokens(<<char, rest::binary>>, depth, in_parens, current, acc) do
    case {char, depth, in_parens} do
      {?(, _, false} ->
        split_type_tokens(rest, depth + 1, true, current <> <<char>>, acc)

      {?(, _, true} ->
        split_type_tokens(rest, depth + 1, true, current <> <<char>>, acc)

      {?), 1, true} ->
        split_type_tokens(rest, depth - 1, false, current <> <<char>>, acc)

      {?), depth, true} when depth > 1 ->
        split_type_tokens(rest, depth - 1, true, current <> <<char>>, acc)

      {?\s, 0, false} ->
        split_type_tokens(rest, depth, false, "", finalize_type_token(acc, current))

      _ ->
        split_type_tokens(rest, depth, in_parens, current <> <<char>>, acc)
    end
  end

  defp finalize_type_token(acc, current) do
    case String.trim(current) do
      "" -> acc
      token -> [token | acc]
    end
  end
end
