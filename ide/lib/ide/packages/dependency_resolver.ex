defmodule Ide.Packages.DependencyResolver do
  @moduledoc false

  alias Ide.Packages.VersionResolver

  @type callbacks :: %{
          required(:versions) => (String.t() -> {:ok, [String.t()]} | {:error, term()}),
          required(:release) => (String.t(), String.t() -> {:ok, map()} | {:error, term()})
        }

  @doc """
  Re-solves `dependencies` after removing a **direct** package.

  Returns new `direct` and `indirect` version maps (pinned versions), or an error if
  the package was not a direct dependency or resolution fails.
  """
  @spec resolve_after_removing_direct(map(), String.t(), callbacks()) ::
          {:ok, map()} | {:error, map()}
  def resolve_after_removing_direct(section_map, removed_package, callbacks)
      when is_map(section_map) and is_binary(removed_package) do
    direct_existing = normalize_dependency_map(section_map["direct"])

    if Map.has_key?(direct_existing, removed_package) do
      direct_remaining = Map.delete(direct_existing, removed_package)
      direct_roots = Map.keys(direct_remaining)

      requirements =
        Enum.reduce(direct_remaining, %{}, fn {pkg, version}, acc ->
          add_requirement(acc, pkg, to_string(version))
        end)

      state = %{versions_cache: %{}, release_cache: %{}}

      case solve(requirements, %{}, direct_roots, callbacks, state) do
        {:ok, assigned, solved_state} ->
          reachable = reachable_packages(direct_roots, assigned, callbacks, solved_state)

          indirect =
            MapSet.difference(reachable, MapSet.new(direct_roots))
            |> MapSet.to_list()
            |> Enum.sort()

          direct_versions =
            direct_roots
            |> Enum.map(&{&1, Map.fetch!(assigned, &1)})
            |> Enum.into(%{})
            |> sort_map()

          indirect_versions =
            indirect
            |> Enum.map(&{&1, Map.fetch!(assigned, &1)})
            |> Enum.into(%{})
            |> sort_map()

          {:ok,
           %{
             direct: direct_versions,
             indirect: indirect_versions,
             removed: removed_package,
             assignments: assigned
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, %{kind: :not_direct_dependency, package: removed_package}}
    end
  end

  @spec resolve(map(), String.t(), String.t(), callbacks()) :: {:ok, map()} | {:error, map()}
  def resolve(section_map, package, scope, callbacks) when is_map(section_map) do
    direct_existing = normalize_dependency_map(section_map["direct"])
    indirect_existing = normalize_dependency_map(section_map["indirect"])
    _ = indirect_existing

    direct_roots =
      case scope do
        "indirect" -> Map.keys(direct_existing)
        _ -> Map.keys(direct_existing) |> ensure_includes(package)
      end

    requirements =
      direct_existing
      |> Enum.reduce(%{}, fn {pkg, version}, acc ->
        add_requirement(acc, pkg, to_string(version))
      end)
      |> then(fn req ->
        case scope do
          "indirect" -> req
          _ -> add_requirement(req, package, "")
        end
      end)

    state = %{versions_cache: %{}, release_cache: %{}}

    case solve(requirements, %{}, direct_roots, callbacks, state) do
      {:ok, assigned, solved_state} ->
        reachable = reachable_packages(direct_roots, assigned, callbacks, solved_state)

        indirect =
          MapSet.difference(reachable, MapSet.new(direct_roots))
          |> MapSet.to_list()
          |> Enum.sort()

        direct_versions =
          direct_roots
          |> Enum.map(&{&1, Map.fetch!(assigned, &1)})
          |> Enum.into(%{})
          |> sort_map()

        indirect_versions =
          indirect
          |> Enum.map(&{&1, Map.fetch!(assigned, &1)})
          |> Enum.into(%{})
          |> sort_map()

        {:ok,
         %{
           direct: direct_versions,
           indirect: indirect_versions,
           selected_version: Map.get(assigned, package),
           assignments: assigned
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec solve(term(), term(), term(), term(), term()) :: term()
  defp solve(requirements, assigned, roots, callbacks, state) do
    unresolved =
      requirements
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(assigned, &1))

    if unresolved == [] do
      {:ok, assigned, state}
    else
      case choose_next(unresolved, requirements, callbacks, state) do
        {:ok, package, candidates, state2} ->
          try_candidates(package, candidates, requirements, assigned, roots, callbacks, state2)

        {:error, reason, state2} ->
          {:error, annotate_conflict(reason, requirements), state2}
      end
      |> case do
        {:ok, assigned2, state3} -> {:ok, assigned2, state3}
        {:error, reason, _state3} -> {:error, reason}
      end
    end
  end

  @spec try_candidates(term(), term(), term(), term(), term(), term(), term()) :: term()
  defp try_candidates(package, [], _requirements, _assigned, _roots, _callbacks, state) do
    {:error, %{kind: :no_compatible_version, package: package}, state}
  end

  defp try_candidates(package, [version | rest], requirements, assigned, roots, callbacks, state) do
    assigned2 = Map.put(assigned, package, version)

    case fetch_release_deps(package, version, callbacks, state) do
      {:ok, dep_constraints, state2} ->
        requirements2 =
          Enum.reduce(dep_constraints, requirements, fn {dep_pkg, constraint}, acc ->
            add_requirement(acc, dep_pkg, constraint)
          end)

        if compatible_assignments?(assigned2, requirements2) do
          case solve(requirements2, assigned2, roots, callbacks, state2) do
            {:ok, solved, solved_state} ->
              {:ok, solved, solved_state}

            {:error, _reason} ->
              try_candidates(package, rest, requirements, assigned, roots, callbacks, state2)
          end
        else
          try_candidates(package, rest, requirements, assigned, roots, callbacks, state2)
        end

      {:error, _reason, state2} ->
        try_candidates(package, rest, requirements, assigned, roots, callbacks, state2)
    end
  end

  @spec choose_next(term(), term(), term(), term()) :: term()
  defp choose_next(unresolved, requirements, callbacks, state) do
    Enum.reduce_while(unresolved, {:ok, nil, nil, state}, fn package,
                                                             {:ok, best_pkg, best_cands, st} ->
      constraints = Map.get(requirements, package, [])

      case candidates_for(package, constraints, callbacks, st) do
        {:ok, candidates, st2} when candidates == [] ->
          {:halt, {:error, %{kind: :no_compatible_version, package: package}, st2}}

        {:ok, candidates, st2} ->
          pick? =
            is_nil(best_pkg) or
              length(candidates) < length(best_cands) or
              (length(candidates) == length(best_cands) and
                 length(constraints) > length(Map.get(requirements, best_pkg, [])))

          if pick? do
            {:cont, {:ok, package, candidates, st2}}
          else
            {:cont, {:ok, best_pkg, best_cands, st2}}
          end

        {:error, reason, st2} ->
          {:halt, {:error, %{kind: :versions_unavailable, package: package, reason: reason}, st2}}
      end
    end)
  end

  @spec candidates_for(term(), term(), term(), term()) :: term()
  defp candidates_for(package, constraints, callbacks, state) do
    with {:ok, versions, state2} <- fetch_versions(package, callbacks, state) do
      candidates =
        versions
        |> Enum.filter(fn version ->
          Enum.all?(constraints, &VersionResolver.satisfies_constraint?(version, &1))
        end)

      {:ok, candidates, state2}
    else
      {:error, reason, state2} -> {:error, reason, state2}
    end
  end

  @spec compatible_assignments?(term(), term()) :: term()
  defp compatible_assignments?(assigned, requirements) do
    Enum.all?(assigned, fn {package, version} ->
      constraints = Map.get(requirements, package, [])
      Enum.all?(constraints, &VersionResolver.satisfies_constraint?(version, &1))
    end)
  end

  @spec fetch_versions(term(), term(), term()) :: term()
  defp fetch_versions(package, callbacks, state) do
    case state.versions_cache do
      %{^package => versions} ->
        {:ok, versions, state}

      _ ->
        case callbacks.versions.(package) do
          {:ok, versions} ->
            sorted =
              versions
              |> Enum.map(&to_string/1)
              |> Enum.uniq()
              |> Enum.sort(
                &(Version.compare(normalize_version(&1), normalize_version(&2)) == :gt)
              )

            {:ok, sorted, put_in(state.versions_cache[package], sorted)}

          {:error, reason} ->
            {:error, reason, state}
        end
    end
  end

  @spec fetch_release_deps(term(), term(), term(), term()) :: term()
  defp fetch_release_deps(package, version, callbacks, state) do
    key = {package, version}

    case state.release_cache do
      %{^key => deps} ->
        {:ok, deps, state}

      _ ->
        case callbacks.release.(package, version) do
          {:ok, elm_json} when is_map(elm_json) ->
            deps = extract_dependency_constraints(elm_json)
            {:ok, deps, put_in(state.release_cache[key], deps)}

          {:error, reason} ->
            {:error, reason, state}
        end
    end
  end

  @spec extract_dependency_constraints(term()) :: term()
  defp extract_dependency_constraints(elm_json) do
    deps = Map.get(elm_json, "dependencies", %{})

    cond do
      is_map(deps) and Map.has_key?(deps, "direct") ->
        merge_constraint_maps([deps["direct"], deps["indirect"]])

      is_map(deps) ->
        merge_constraint_maps([deps])

      true ->
        %{}
    end
  end

  @spec merge_constraint_maps(term()) :: term()
  defp merge_constraint_maps(maps) do
    maps
    |> Enum.map(&normalize_dependency_map/1)
    |> Enum.reduce(%{}, fn map, acc -> Map.merge(acc, map) end)
  end

  @spec normalize_dependency_map(term()) :: term()
  defp normalize_dependency_map(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {pkg, constraint}, acc ->
      if is_binary(pkg) and (is_binary(constraint) or is_number(constraint)) do
        Map.put(acc, pkg, to_string(constraint))
      else
        acc
      end
    end)
  end

  defp normalize_dependency_map(_), do: %{}

  @spec add_requirement(term(), term(), term()) :: term()
  defp add_requirement(requirements, package, constraint) when is_binary(package) do
    existing = Map.get(requirements, package, [])
    normalized = normalize_constraint(constraint)
    updated = if normalized in existing, do: existing, else: existing ++ [normalized]
    Map.put(requirements, package, updated)
  end

  @spec normalize_constraint(term()) :: term()
  defp normalize_constraint(nil), do: ""
  defp normalize_constraint(value), do: to_string(value)

  @spec annotate_conflict(term(), term()) :: term()
  defp annotate_conflict(reason, requirements) do
    case reason do
      %{package: package} = map ->
        Map.put_new(map, :constraints, Map.get(requirements, package, []))

      other ->
        %{kind: :resolution_failed, reason: other}
    end
  end

  @spec reachable_packages(term(), term(), term(), term()) :: term()
  defp reachable_packages(roots, assigned, callbacks, state) do
    traverse(roots, MapSet.new(), assigned, callbacks, state)
  end

  @spec traverse(term(), term(), term(), term(), term()) :: term()
  defp traverse([], seen, _assigned, _callbacks, _state), do: seen

  defp traverse([package | rest], seen, assigned, callbacks, state) do
    if MapSet.member?(seen, package) do
      traverse(rest, seen, assigned, callbacks, state)
    else
      case Map.get(assigned, package) do
        nil ->
          traverse(rest, MapSet.put(seen, package), assigned, callbacks, state)

        version ->
          deps =
            case fetch_release_deps(package, version, callbacks, state) do
              {:ok, dep_constraints, _state2} -> Map.keys(dep_constraints)
              _ -> []
            end

          traverse(rest ++ deps, MapSet.put(seen, package), assigned, callbacks, state)
      end
    end
  end

  @spec ensure_includes(term(), term()) :: term()
  defp ensure_includes(list, value), do: if(value in list, do: list, else: list ++ [value])

  @spec normalize_version(term()) :: term()
  defp normalize_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end

  @spec sort_map(term()) :: term()
  defp sort_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.into(%{})
  end
end
