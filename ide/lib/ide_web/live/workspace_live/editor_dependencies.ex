defmodule IdeWeb.WorkspaceLive.EditorDependencies do
  @moduledoc false

  alias Ide.EditorCompletion.Types, as: CompletionTypes
  alias Ide.Packages
  alias Ide.Packages.Types, as: PackageTypes
  alias Ide.Projects
  alias Ide.Projects.Project

  @type dependency_row :: CompletionTypes.dependency_row()

  @type dependency_payload :: %{
          direct: [dependency_row()],
          indirect: [dependency_row()],
          dependencies_available?: boolean()
        }

  @type docs_payload :: %{
          package_doc_index: CompletionTypes.package_doc_index(),
          editor_doc_packages: [CompletionTypes.doc_package_row()]
        }

  @type editor_payload :: %{
          required(:direct) => [dependency_row()],
          required(:indirect) => [dependency_row()],
          optional(:dependencies_available?) => boolean(),
          required(:package_doc_index) => CompletionTypes.package_doc_index(),
          required(:editor_doc_packages) => [CompletionTypes.doc_package_row()]
        }

  @spec build_payload(Project.t(), String.t(), String.t()) :: editor_payload()
  def build_payload(project, packages_root, doc_root)
      when is_map(project) and is_binary(packages_root) and is_binary(doc_root) do
    deps = build_dependency_payload(project, packages_root)
    docs = build_docs_payload(project, doc_root)

    Map.merge(deps, docs)
  end

  @spec build_dependency_payload(Project.t(), String.t()) :: dependency_payload()
  def build_dependency_payload(project, packages_root)
      when is_map(project) and is_binary(packages_root) do
    read_dependency_lists(project, packages_root, usage: true)
  end

  @spec build_docs_payload(Project.t(), String.t()) :: docs_payload()
  def build_docs_payload(project, doc_root)
      when is_map(project) and is_binary(doc_root) do
    platform_target =
      case doc_root do
        "watch" -> :watch
        "phone" -> :phone
        _ -> :none
      end

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
        {:ok, rows} -> enrich_editor_doc_packages(rows)
      end

    %{
      package_doc_index: package_doc_index,
      editor_doc_packages: editor_doc_packages
    }
  end

  @spec read_dependency_lists(Project.t(), String.t(), keyword()) :: dependency_payload()
  def read_dependency_lists(project, packages_root, opts \\ [])
      when is_map(project) and is_binary(packages_root) and is_list(opts) do
    include_usage? = Keyword.get(opts, :usage, false)

    {direct, indirect, dependencies_available?} =
      case Projects.read_source_file(project, packages_root, "elm.json") do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"dependencies" => %{"direct" => d, "indirect" => i}}}
            when is_map(d) and is_map(i) ->
              {normalize_dep_list(project, d, packages_root, include_usage?),
               normalize_dep_list(project, i, packages_root, include_usage?), true}

            {:ok, %{"dependencies" => deps}} when is_map(deps) ->
              # Be permissive if an elm.json uses package-style dependencies
              # or a partially shaped app dependency block.
              direct = deps |> Map.get("direct", deps)
              indirect = deps |> Map.get("indirect", %{})

              if is_map(direct) and is_map(indirect) do
                {normalize_dep_list(project, direct, packages_root, include_usage?),
                 normalize_dep_list(project, indirect, packages_root, include_usage?), true}
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

  @spec normalize_dep_list(Project.t(), PackageTypes.dependency_versions_map(), String.t(), boolean()) ::
          [dependency_row()]
  defp normalize_dep_list(project, map, packages_root, include_usage?) when is_map(map) do
    packages = Map.keys(map)

    usage =
      if include_usage?,
        do: Packages.package_usage(project, packages, source_root: packages_root),
        else: %{}

    map
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, ver} ->
      %{
        name: name,
        version: to_string(ver),
        builtin?: Packages.pebble_builtin_package?(name, packages_root),
        used?: if(include_usage?, do: Map.get(usage, name, false), else: nil)
      }
    end)
  end

  @spec enrich_editor_doc_packages([PackageTypes.doc_catalog_entry()]) ::
          [CompletionTypes.doc_package_row()]
  defp enrich_editor_doc_packages(rows) when is_list(rows) do
    Enum.map(rows, fn row ->
      package = row[:package] || row["package"]

      case Packages.builtin_package_docs(package) do
        {:ok, docs} when docs != [] -> Map.put(row, :docs, docs)
        _ -> row
      end
    end)
  end
end
