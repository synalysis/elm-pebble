defmodule Ide.Packages.VersionResolver do
  @moduledoc false

  @spec resolve_best([String.t()], String.t() | nil) ::
          {:ok, String.t()} | {:error, :no_versions | :no_compatible_version}
  def resolve_best(versions, constraint) when is_list(versions) do
    sorted =
      versions
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.filter(&semver?/1)
      |> Enum.sort(&(Version.compare(normalize(&1), normalize(&2)) == :gt))

    cond do
      sorted == [] ->
        {:error, :no_versions}

      blank_constraint?(constraint) ->
        {:ok, List.first(sorted)}

      true ->
        case Enum.find(sorted, &satisfies_constraint?(&1, constraint)) do
          nil -> {:error, :no_compatible_version}
          match -> {:ok, match}
        end
    end
  end

  @spec satisfies_constraint?(String.t(), String.t() | nil) :: boolean()
  def satisfies_constraint?(_version, nil), do: true
  def satisfies_constraint?(_version, ""), do: true

  def satisfies_constraint?(version, constraint) do
    parts =
      constraint
      |> String.split("||")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Enum.any?(parts, fn part ->
      (exact_semver?(part) and Version.compare(normalize(version), normalize(part)) == :eq) or
        comparator_constraint_match?(version, part)
    end)
  end

  @spec comparator_constraint_match?(term(), term()) :: term()
  defp comparator_constraint_match?(version, constraint_part) do
    rewritten =
      constraint_part
      |> rewrite_left_comparison()
      |> String.replace(~r/\bv\b/, " ")

    comparators =
      Regex.scan(~r/(<=|>=|<|>|==)\s*([0-9]+\.[0-9]+\.[0-9]+)/, rewritten)
      |> Enum.map(fn [_, op, comp_version] -> {op, comp_version} end)

    comparators != [] and Enum.all?(comparators, &match_comparator?(version, &1))
  end

  @spec rewrite_left_comparison(term()) :: term()
  defp rewrite_left_comparison(constraint) do
    constraint
    |> then(&Regex.replace(~r/([0-9]+\.[0-9]+\.[0-9]+)\s*<=\s*v/, &1, "v >= \\1"))
    |> then(&Regex.replace(~r/([0-9]+\.[0-9]+\.[0-9]+)\s*<\s*v/, &1, "v > \\1"))
    |> then(&Regex.replace(~r/([0-9]+\.[0-9]+\.[0-9]+)\s*>=\s*v/, &1, "v <= \\1"))
    |> then(&Regex.replace(~r/([0-9]+\.[0-9]+\.[0-9]+)\s*>\s*v/, &1, "v < \\1"))
  end

  @spec match_comparator?(term(), term()) :: term()
  defp match_comparator?(version, {op, cmp_version}) do
    compare = Version.compare(normalize(version), normalize(cmp_version))

    case op do
      "==" -> compare == :eq
      "<" -> compare == :lt
      "<=" -> compare in [:lt, :eq]
      ">" -> compare == :gt
      ">=" -> compare in [:gt, :eq]
      _ -> false
    end
  end

  @spec blank_constraint?(term()) :: term()
  defp blank_constraint?(constraint),
    do: is_nil(constraint) or String.trim(to_string(constraint)) == ""

  @spec exact_semver?(term()) :: term()
  defp exact_semver?(value), do: semver?(value)
  @spec semver?(term()) :: term()
  defp semver?(value), do: String.match?(value, ~r/^\d+\.\d+\.\d+$/)

  @spec normalize(term()) :: term()
  defp normalize(value) do
    case String.split(value, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> value
    end
  end
end
