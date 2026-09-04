defmodule ElmEx.Typesys.Oracle do
  @moduledoc """
  Compare typesys accept/reject with official `elm make --report=json`.
  """

  alias ElmEx.Frontend.Bridge

  @type verdict :: :accept | :reject

  @spec typesys_verdict(String.t()) :: {:ok, verdict(), [map()]} | {:error, term()}
  def typesys_verdict(project_dir) when is_binary(project_dir) do
    case Bridge.load_project(project_dir, lowerer_diagnostics: false) do
      {:ok, project} ->
        diags =
          project.diagnostics
          |> Enum.filter(&error?/1)
          |> Enum.filter(&typesys?/1)
        verdict = if diags == [], do: :accept, else: :reject
        {:ok, verdict, diags}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec elm_make_verdict(String.t()) :: {:ok, verdict(), String.t()} | {:skip, String.t()} | {:error, term()}
  def elm_make_verdict(project_dir) when is_binary(project_dir) do
    elm = elm_executable()

    if is_nil(elm) do
      {:skip, "elm binary not on PATH"}
    else
      entry =
        cond do
          File.exists?(Path.join(project_dir, "src/Main.elm")) -> "src/Main.elm"
          true ->
            project_dir
            |> Path.join("src/**/*.elm")
            |> Path.wildcard()
            |> List.first()
        end

      if is_nil(entry) do
        {:error, :no_elm_sources}
      else
        {out, status} =
          System.cmd(
            elm,
            ["make", Path.relative_to(entry, project_dir), "--report=json", "--output=/tmp/elmc-typesys-oracle.js"],
            cd: project_dir,
            stderr_to_stdout: true
          )

        cond do
          status == 0 ->
            {:ok, :accept, out}

            String.contains?(out, "compile-errors") or String.contains?(out, "TYPE MISMATCH") or
              String.contains?(out, "NAMING ERROR") or String.contains?(out, "MISSING PATTERNS") or
              String.contains?(out, "PORT ERROR") or String.contains?(out, "PORT PROBLEM") ->
            {:ok, :reject, out}

          true ->
            {:skip, out}
        end
      end
    end
  end

  @family_by_code %{
    "type_mismatch" => "TYPE MISMATCH",
    "unbound_value" => "NAMING ERROR",
    "missing_patterns" => "MISSING PATTERNS",
    "unreachable_pattern" => "REDUNDANT PATTERN",
    "ambiguous_import" => "NAMING ERROR",
    "port_problem" => "PORT PROBLEM",
    "duplicate_declaration" => "NAMING ERROR",
    "duplicate_pattern" => "NAMING ERROR",
    "duplicate_type" => "NAMING ERROR",
    "recursive_alias" => "RECURSIVE ALIAS",
    "module_name_mismatch" => "MODULE NAME MISMATCH",
    "bad_exposing" => "BAD EXPORT",
    "value_cycle" => "BAD RECURSION",
    "bad_tuple" => "BAD TUPLE",
    "function_call_arity" => "TOO MANY ARGS",
    "too_many_args" => "TOO MANY ARGS",
    "too_few_args" => "TOO FEW ARGS",
    "unsupported_expr" => "UNSUPPORTED_EXPR"
  }

  @spec family(String.t()) :: String.t()
  def family(code) when is_binary(code), do: Map.get(@family_by_code, code, String.upcase(code))

  @doc """
  Official Elm sometimes uses a more specific title for the same family
  (e.g. `TOO MANY ARGS` instead of `TYPE MISMATCH`).
  """
  @spec families_overlap?([String.t()], [String.t()]) :: boolean()
  def families_overlap?(typesys_families, elm_families)
      when is_list(typesys_families) and is_list(elm_families) do
    expanded =
      typesys_families
      |> Enum.flat_map(&related_families/1)
      |> MapSet.new()

    MapSet.size(MapSet.intersection(expanded, MapSet.new(elm_families))) > 0
  end

  defp related_families("TYPE MISMATCH"), do: ["TYPE MISMATCH", "TOO MANY ARGS"]
  defp related_families("TOO MANY ARGS"), do: ["TOO MANY ARGS", "TYPE MISMATCH"]
  defp related_families("TOO FEW ARGS"), do: ["TOO FEW ARGS"]
  defp related_families("NAMING ERROR"), do: ["NAMING ERROR", "AMBIGUOUS NAME"]
  defp related_families("MISSING PATTERNS"), do: ["MISSING PATTERNS", "UNSAFE PATTERN"]
  defp related_families("BAD RECURSION"), do: ["BAD RECURSION", "RECURSIVE VALUE", "CYCLIC DEFINITION"]
  defp related_families("TUPLE ISSUE"), do: ["TUPLE ISSUE", "BAD TUPLE", "PARSE ERROR", "SYNTAX PROBLEM"]
  defp related_families("BAD TUPLE"), do: ["BAD TUPLE", "TUPLE ISSUE", "PARSE ERROR"]
  defp related_families("SYNTAX PROBLEM"), do: ["SYNTAX PROBLEM", "BAD EXPOSING", "BAD EXPORT", "PARSE ERROR"]
  defp related_families("BAD EXPORT"), do: ["BAD EXPORT", "BAD EXPOSING", "SYNTAX PROBLEM"]
  defp related_families("UNSUPPORTED_EXPR"), do: ["UNSUPPORTED_EXPR", "PARSE ERROR", "TUPLE ISSUE", "BAD TUPLE"]
  defp related_families("PORT PROBLEM"), do: ["PORT PROBLEM", "PORT ERROR"]
  defp related_families(other), do: [other]

  @spec compare(String.t()) ::
          {:ok,
           %{
             typesys: verdict(),
             elm: verdict() | :skip,
             typesys_families: [String.t()],
             elm_families: [String.t()]
           }}
          | {:error, term()}
  def compare(project_dir) when is_binary(project_dir) do
    with {:ok, typesys, diags} <- typesys_verdict(project_dir) do
      typesys_families =
        diags
        |> Enum.map(&diag_family/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      case elm_make_verdict(project_dir) do
        {:ok, elm, raw} ->
          {:ok,
           %{
             typesys: typesys,
             elm: elm,
             typesys_families: typesys_families,
             elm_families: elm_titles(raw)
           }}

        {:skip, _} ->
          {:ok,
           %{
             typesys: typesys,
             elm: :skip,
             typesys_families: typesys_families,
             elm_families: []
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp diag_family(diag) when is_map(diag) do
    code = Map.get(diag, "code", Map.get(diag, :code))
    if is_binary(code), do: family(code), else: nil
  end

  defp diag_family(_), do: nil

  defp elm_titles(raw) when is_binary(raw) do
    titles =
      case Jason.decode(raw) do
        {:ok, decoded} -> titles_from_report(decoded)
        _ -> []
      end

    if titles == [] do
      Regex.scan(~r/"title"\s*:\s*"([^"]+)"/, raw)
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.uniq()
    else
      titles
    end
  end

  defp titles_from_report(%{"errors" => errors}) when is_list(errors) do
    errors
    |> Enum.flat_map(&problem_titles/1)
    |> Enum.uniq()
  end

  defp titles_from_report(%{"type" => "compile-errors", "errors" => errors}) when is_list(errors) do
    titles_from_report(%{"errors" => errors})
  end

  defp titles_from_report(_), do: []

  defp problem_titles(%{"problems" => problems}) when is_list(problems) do
    Enum.flat_map(problems, fn
      %{"title" => title} when is_binary(title) -> [title]
      _ -> []
    end)
  end

  defp problem_titles(_), do: []

  # asdf's `elm` shim looks for `.tool-versions` in cwd; temp oracle
  # projects do not have one, so resolve the real binary first.
  defp elm_executable do
    System.get_env("ELM_BINARY") || resolve_asdf_elm() || System.find_executable("elm")
  end

  defp resolve_asdf_elm do
    asdf = System.find_executable("asdf")

    if is_binary(asdf) do
      Enum.find_value(asdf_search_dirs(), fn dir ->
        case System.cmd(asdf, ["which", "elm"], cd: dir, stderr_to_stdout: true) do
          {path, 0} ->
            path = String.trim(path)

            if File.regular?(path) and not String.contains?(path, "/shims/") do
              path
            else
              nil
            end

          _ ->
            nil
        end
      end)
    end
  end

  defp asdf_search_dirs do
    cwd = File.cwd!()
    [cwd, Path.expand("..", cwd), System.user_home!()]
  end

  defp error?(diag) when is_map(diag) do
    Map.get(diag, "severity", Map.get(diag, :severity, "warning")) in ["error", :error]
  end

  defp error?(_), do: false

  defp typesys?(diag) when is_map(diag) do
    Map.get(diag, "source", Map.get(diag, :source)) == "elm_ex/typesys"
  end

  defp typesys?(_), do: false
end
