defmodule Ide.Packages.ElmJsonEditor do
  @moduledoc false

  alias Ide.Packages.DependencyResolver
  alias Ide.Projects

  @spec preview_add(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def preview_add(project, package, opts) do
    with {:ok, root, decoded} <- load_elm_json(project, opts[:source_root]),
         section <- normalize_section(opts[:section]),
         scope <- normalize_scope(opts[:scope]),
         section_map <- Map.get(decoded, section, %{}) |> ensure_map(),
         callbacks <- build_callbacks(opts),
         {:ok, resolved} <- DependencyResolver.resolve(section_map, package, scope, callbacks),
         {constraint, location} <- existing_constraint(decoded, package) do
      {:ok,
       %{
         source_root: root,
         rel_path: "elm.json",
         package: package,
         section: section,
         scope: scope,
         selected_version: resolved.selected_version,
         existing_constraint: constraint,
         existing_location: location,
         already_present: not is_nil(constraint),
         resolved_direct: resolved.direct,
         resolved_indirect: resolved.indirect
       }}
    end
  end

  @spec preview_remove(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def preview_remove(project, package, opts) do
    with {:ok, root, decoded} <- load_elm_json(project, opts[:source_root]),
         section <- normalize_section(opts[:section] || "dependencies"),
         section_map <- Map.get(decoded, section, %{}) |> ensure_map(),
         callbacks <- build_callbacks(opts),
         {:ok, resolved} <-
           DependencyResolver.resolve_after_removing_direct(section_map, package, callbacks) do
      {:ok,
       %{
         source_root: root,
         rel_path: "elm.json",
         package: package,
         section: section,
         resolved_direct: resolved.direct,
         resolved_indirect: resolved.indirect,
         removed: resolved.removed
       }}
    end
  end

  @spec remove_package(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def remove_package(project, package, opts) do
    with {:ok, root, decoded, original_json} <-
           load_elm_json(project, opts[:source_root], include_text: true),
         {:ok, preview} <- preview_remove(project, package, opts),
         {updated, previous_version} <- apply_removal(decoded, preview),
         encoded <- Jason.encode!(updated, pretty: true) <> "\n",
         :ok <- maybe_write(project, root, encoded, original_json) do
      {:ok,
       Map.merge(preview, %{
         changed: encoded != original_json,
         previous_version: previous_version,
         dependency_diff: %{
           package: package,
           from: previous_version,
           to: nil,
           section: preview.section
         }
       })}
    end
  end

  @spec add_package(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_package(project, package, opts) do
    with {:ok, root, decoded, original_json} <-
           load_elm_json(project, opts[:source_root], include_text: true),
         {:ok, preview} <- preview_add(project, package, opts),
         {updated, previous_version} <- apply_dependency(decoded, preview),
         encoded <- Jason.encode!(updated, pretty: true) <> "\n",
         :ok <- maybe_write(project, root, encoded, original_json) do
      {:ok,
       Map.merge(preview, %{
         changed: encoded != original_json,
         previous_version: previous_version,
         dependency_diff: %{
           package: package,
           from: previous_version,
           to: preview.selected_version,
           section: preview.section,
           scope: preview.scope
         }
       })}
    end
  end

  @spec candidate_roots(map()) :: [String.t()]
  def candidate_roots(project) do
    prioritized = ["watch", "protocol", "phone"]
    source_roots = Map.get(project, :source_roots, [])
    (prioritized ++ source_roots) |> Enum.uniq()
  end

  @doc """
  Roots whose `elm.json` may receive package add/remove from the IDE Packages pane.

  Omits `protocol` — that tree is for shared protocol types, not third-party Elm deps.
  """
  @spec roots_for_package_management(map()) :: [String.t()]
  def roots_for_package_management(project) do
    project |> candidate_roots() |> Enum.reject(&(&1 == "protocol"))
  end

  @spec maybe_write(term(), term(), term(), term()) :: term()
  defp maybe_write(_project, _root, encoded, original) when encoded == original, do: :ok

  defp maybe_write(project, root, encoded, _original) do
    Projects.write_source_file(project, root, "elm.json", encoded)
  end

  @spec apply_dependency(term(), term()) :: term()
  defp apply_dependency(decoded, preview) do
    section = preview.section
    package = preview.package

    section_map = Map.get(decoded, section, %{}) |> ensure_map()
    previous = previous_version(section_map, package)

    next_section =
      section_map
      |> Map.put("direct", preview.resolved_direct)
      |> Map.put("indirect", preview.resolved_indirect)
      |> ensure_ordered_map()

    updated = decoded |> Map.put(section, next_section) |> ensure_ordered_map()
    {updated, previous}
  end

  @spec apply_removal(term(), term()) :: term()
  defp apply_removal(decoded, preview) do
    section = preview.section
    package = preview.package

    section_map = Map.get(decoded, section, %{}) |> ensure_map()
    previous = previous_version(section_map, package)

    next_section =
      section_map
      |> Map.put("direct", preview.resolved_direct)
      |> Map.put("indirect", preview.resolved_indirect)
      |> ensure_ordered_map()

    updated = decoded |> Map.put(section, next_section) |> ensure_ordered_map()
    {updated, previous}
  end

  @spec load_elm_json(term(), term(), term()) :: term()
  defp load_elm_json(project, preferred_root, opts \\ []) do
    include_text? = opts[:include_text] || false

    candidates =
      [preferred_root | candidate_roots(project)] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Enum.reduce_while(candidates, {:error, :elm_json_not_found}, fn root, _acc ->
      case Projects.read_source_file(project, root, "elm.json") do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, decoded} when is_map(decoded) ->
              if include_text?,
                do: {:halt, {:ok, root, decoded, content}},
                else: {:halt, {:ok, root, decoded}}

            {:ok, _other} ->
              {:halt, {:error, :invalid_elm_json}}

            {:error, reason} ->
              {:halt, {:error, {:invalid_elm_json, reason}}}
          end

        {:error, _reason} ->
          {:cont, {:error, :elm_json_not_found}}
      end
    end)
  end

  @spec existing_constraint(term(), term()) :: term()
  defp existing_constraint(decoded, package) do
    sections = ["dependencies", "test-dependencies"]
    scopes = ["direct", "indirect"]

    Enum.find_value(sections, {nil, nil}, fn section ->
      section_map = Map.get(decoded, section, %{}) |> ensure_map()

      Enum.find_value(scopes, fn scope ->
        scope_map = Map.get(section_map, scope, %{}) |> ensure_map()

        case Map.get(scope_map, package) do
          nil -> nil
          value -> {to_string(value), "#{section}.#{scope}"}
        end
      end)
    end)
  end

  @spec build_callbacks(term()) :: term()
  defp build_callbacks(opts) do
    %{
      versions: Keyword.fetch!(opts, :versions_fetcher),
      release: Keyword.fetch!(opts, :release_fetcher)
    }
  end

  @spec previous_version(term(), term()) :: term()
  defp previous_version(section_map, package) do
    direct = section_map |> Map.get("direct", %{}) |> ensure_map()
    indirect = section_map |> Map.get("indirect", %{}) |> ensure_map()
    Map.get(direct, package) || Map.get(indirect, package)
  end

  @spec normalize_section(term()) :: term()
  defp normalize_section(nil), do: "dependencies"
  defp normalize_section("test"), do: "test-dependencies"
  defp normalize_section("test-dependencies"), do: "test-dependencies"
  defp normalize_section("dependencies"), do: "dependencies"
  defp normalize_section(_), do: "dependencies"

  @spec normalize_scope(term()) :: term()
  defp normalize_scope(nil), do: "direct"
  defp normalize_scope("direct"), do: "direct"
  defp normalize_scope("indirect"), do: "indirect"
  defp normalize_scope(_), do: "direct"

  @spec ensure_map(term()) :: term()
  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_), do: %{}

  @spec ensure_ordered_map(term()) :: term()
  defp ensure_ordered_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.into(%{})
  end
end
