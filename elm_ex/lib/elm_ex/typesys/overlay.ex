defmodule ElmEx.Typesys.Overlay do
  @moduledoc """
  Typesys-only extra modules that exist on disk for compile but may be
  missing from a check-only tree (generated Resources, protocol Types).

  Overlays are stripped after check so codegen does not compile the stubs.
  """

  alias ElmEx.Frontend.{GeneratedParser, Project}
  alias ElmEx.Typesys.GeneratedResources

  @companion_types "Companion.Types"
  @bundled_types_rel "ide/priv/internal_packages/companion-protocol/src/Companion/Types.elm"

  @type overlay_state :: %{names: MapSet.t(String.t()), originals: [ElmEx.Frontend.Module.t()]}

  @spec attach(Project.t()) :: {Project.t(), overlay_state()}
  def attach(%Project{} = project) do
    {project, names, originals} = GeneratedResources.attach(project)
    {project, companion_names} = attach_companion_types(project)

    {project,
     %{
       names: MapSet.union(names, companion_names),
       originals: originals
     }}
  end

  @spec strip([ElmEx.Frontend.Module.t()], overlay_state() | MapSet.t(String.t())) ::
          [ElmEx.Frontend.Module.t()]
  def strip(modules, %{names: names, originals: originals}),
    do: GeneratedResources.strip(modules, names, originals)

  def strip(modules, names), do: GeneratedResources.strip(modules, names)

  defp attach_companion_types(%Project{} = project) do
    cond do
      Enum.any?(project.modules, &(&1.name == @companion_types)) ->
        {project, MapSet.new()}

      not module_imported?(project.modules, @companion_types) ->
        {project, MapSet.new()}

      true ->
        case parse_companion_types(project) do
          {:ok, mod} ->
            {%{project | modules: project.modules ++ [mod]}, MapSet.new([@companion_types])}

          :skip ->
            {project, MapSet.new()}
        end
    end
  end

  defp parse_companion_types(project) do
    case first_existing(companion_types_candidates(project)) do
      nil ->
        :skip

      source_path ->
        path = Path.join(project.project_dir, "src/Companion/Types.elm")

        case File.read(source_path) do
          {:ok, source} ->
            case GeneratedParser.parse_source(path, source) do
              {:ok, mod} -> {:ok, %{mod | path: path}}
              _ -> :skip
            end

          _ ->
            :skip
        end
    end
  end

  defp companion_types_candidates(%Project{project_dir: dir}) when is_binary(dir) do
    near = [
      Path.join(dir, "protocol/src/Companion/Types.elm"),
      Path.expand("../protocol/src/Companion/Types.elm", dir)
    ]

    bundled =
      (ancestor_dirs(dir) ++ ancestor_dirs(File.cwd!()) ++ ancestor_dirs(__DIR__))
      |> Enum.map(&Path.join(&1, @bundled_types_rel))

    Enum.map(near ++ bundled, &Path.expand/1)
  end

  defp first_existing(paths) do
    Enum.find(paths, &File.exists?/1)
  end

  defp ancestor_dirs(dir) when is_binary(dir) do
    dir
    |> Path.expand()
    |> do_ancestor_dirs([])
  end

  defp do_ancestor_dirs(dir, acc) do
    parent = Path.dirname(dir)

    if parent == dir do
      Enum.reverse(acc)
    else
      do_ancestor_dirs(parent, [dir | acc])
    end
  end

  defp module_imported?(modules, name) do
    Enum.any?(modules, fn mod ->
      name in List.wrap(Map.get(mod, :imports)) or
        Enum.any?(List.wrap(Map.get(mod, :import_entries)), &(import_module(&1) == name))
    end)
  end

  defp import_module(%{module: name}) when is_binary(name), do: name
  defp import_module(%{"module" => name}) when is_binary(name), do: name
  defp import_module(_), do: nil
end
