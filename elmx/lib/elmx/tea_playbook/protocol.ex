defmodule Elmx.TeaPlaybook.Protocol do
  @moduledoc """
  Parses `protocol/src/Companion/Types.elm` `PhoneToWatch` for shared TEA playbooks.
  """

  @type phone_ctor :: %{name: String.t(), tag: non_neg_integer(), arity: non_neg_integer()}

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

  @spec phone_tag(String.t(), String.t()) :: non_neg_integer() | nil
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
        |> Enum.with_index()
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
        arity = rest |> String.split() |> Enum.reject(&(&1 == "")) |> length()
        [%{name: name, arity: arity}]

      _ ->
        []
    end
  end
end
