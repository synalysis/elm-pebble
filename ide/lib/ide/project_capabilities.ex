defmodule Ide.ProjectCapabilities do
  @moduledoc false

  alias Ide.Debugger.ElmIntrospect
  alias Ide.ProjectCapabilities.Detect

  @supported ~w(location configurable health)

  @doc """
  Scans watch and phone Elm sources and returns declared Pebble capabilities.
  """
  @spec infer_workspace(String.t()) :: MapSet.t(String.t())
  def infer_workspace(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> elm_files_by_source_root()
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      MapSet.union(acc, infer_file(entry))
    end)
    |> MapSet.intersection(MapSet.new(@supported))
  end

  @doc """
  Infers capabilities from a single Elm module snapshot.
  """
  @spec infer_introspect(map(), String.t()) :: MapSet.t(String.t())
  def infer_introspect(%{} = introspect, source_root) when is_binary(source_root) do
    caps = MapSet.new()

    caps =
      if source_root == "phone" do
        MapSet.union(caps, Detect.phone_caps(introspect))
      else
        caps
      end

    caps =
      if source_root == "watch" do
        MapSet.union(caps, Detect.watch_caps(introspect))
      else
        caps
      end

    caps
    |> MapSet.intersection(MapSet.new(@supported))
  end

  def infer_introspect(_introspect, _source_root), do: MapSet.new()

  @spec infer_file({String.t(), String.t(), String.t()}) :: MapSet.t(String.t())
  defp infer_file({source_root, _path, content}) do
    case ElmIntrospect.analyze_source(content, "ProjectCapabilities.elm") do
      {:ok, %{"elm_introspect" => introspect}} ->
        infer_introspect(introspect, source_root)

      _ ->
        MapSet.new()
    end
  end

  @spec elm_files_by_source_root(String.t()) :: [{String.t(), String.t(), String.t()}]
  defp elm_files_by_source_root(workspace_root) do
    for root <- ["watch", "phone"],
        abs = Path.join(workspace_root, root),
        File.dir?(abs),
        path <- Path.wildcard(Path.join(abs, "**/*.elm")),
        {:ok, content} <- [File.read(path)],
        do: {root, path, content}
  end
end
