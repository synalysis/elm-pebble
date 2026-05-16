defmodule IdeWeb.WorkspaceLive.EditorDependencies do
  @moduledoc false

  alias Ide.Packages
  alias Ide.Projects

  @spec build_payload(map(), String.t(), String.t()) :: %{
          direct: [map()],
          indirect: [map()],
          dependencies_available?: boolean(),
          package_doc_index: map(),
          editor_doc_packages: [map()]
        }
  def build_payload(project, packages_root, doc_root)
      when is_map(project) and is_binary(packages_root) and is_binary(doc_root) do
    platform_target =
      case doc_root do
        "watch" -> :watch
        "phone" -> :phone
        _ -> :none
      end

    deps = read_dependency_lists(project, packages_root)

    package_doc_index =
      case Packages.build_doc_module_index(project,
             source_root: doc_root,
             platform_target: platform_target
           ) do
        {:ok, index} -> index
      end

    editor_doc_packages =
      case Packages.list_doc_package_rows(project,
             source_root: doc_root,
             platform_target: platform_target
           ) do
        {:ok, rows} -> rows
      end

    Map.merge(deps, %{
      package_doc_index: package_doc_index,
      editor_doc_packages: editor_doc_packages
    })
  end

  @spec read_dependency_lists(map(), String.t()) :: %{
          direct: [map()],
          indirect: [map()],
          dependencies_available?: boolean()
        }
  def read_dependency_lists(project, packages_root)
      when is_map(project) and is_binary(packages_root) do
    {direct, indirect, dependencies_available?} =
      case Projects.read_source_file(project, packages_root, "elm.json") do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"dependencies" => %{"direct" => d, "indirect" => i}}}
            when is_map(d) and is_map(i) ->
              {normalize_dep_list(d), normalize_dep_list(i), true}

            {:ok, %{"dependencies" => deps}} when is_map(deps) ->
              # Be permissive if an elm.json uses package-style dependencies
              # or a partially shaped app dependency block.
              direct = deps |> Map.get("direct", deps)
              indirect = deps |> Map.get("indirect", %{})

              if is_map(direct) and is_map(indirect) do
                {normalize_dep_list(direct), normalize_dep_list(indirect), true}
              else
                {[], [], false}
              end

            _ ->
              {[], [], false}
          end

        _ ->
          {[], [], false}
      end

    %{
      direct: direct,
      indirect: indirect,
      dependencies_available?: dependencies_available?
    }
  end

  @spec normalize_dep_list(term()) :: term()
  defp normalize_dep_list(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, ver} ->
      %{
        name: name,
        version: to_string(ver),
        builtin?: Packages.pebble_builtin_package?(name)
      }
    end)
  end
end
