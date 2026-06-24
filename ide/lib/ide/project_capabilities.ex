defmodule Ide.ProjectCapabilities do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.PebblePreferences
  alias Ide.ProjectCapabilities.Detect

  @supported ~w(
    location
    configurable
    health
    watch_accel
    watch_vibes
    dictation
    compass
    data_log
    app_focus
  )

  @package_capabilities ~w(location configurable health)

  @doc """
  Returns true when the companion app exposes preferences or configuration UI.
  """
  @spec companion_preferences?(String.t()) :: boolean()
  def companion_preferences?(workspace_root) when is_binary(workspace_root) do
    phone_root = Path.join(workspace_root, "phone")

    with true <- File.exists?(Path.join(phone_root, "elm.json")),
         false <- preferences_schema?(phone_root) do
      workspace_root
      |> infer_workspace()
      |> MapSet.member?("configurable")
    else
      true -> true
      _ -> false
    end
  end

  @doc """
  Returns Pebble package metadata capabilities inferred from Elm API usage.
  """
  @spec package_capabilities(String.t()) :: [String.t()]
  def package_capabilities(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> infer_workspace()
    |> MapSet.intersection(MapSet.new(@package_capabilities))
    |> maybe_add_preferences_configurable(workspace_root)
    |> MapSet.to_list()
    |> Enum.sort()
  end

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
  @spec infer_introspect(DebuggerTypes.elm_introspect(), String.t()) :: MapSet.t(String.t())
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
    case Ide.Debugger.CompileContract.analyze_source(content, "ProjectCapabilities.elm") do
      {:ok, %{"debugger_contract" => introspect}} ->
        infer_introspect(introspect, source_root)

      _ ->
        MapSet.new()
    end
  end

  @spec maybe_add_preferences_configurable(MapSet.t(String.t()), String.t()) ::
          MapSet.t(String.t())
  defp maybe_add_preferences_configurable(caps, workspace_root) do
    phone_root = Path.join(workspace_root, "phone")

    if preferences_schema?(phone_root) do
      MapSet.put(caps, "configurable")
    else
      caps
    end
  end

  @spec preferences_schema?(String.t()) :: boolean()
  defp preferences_schema?(phone_root) do
    case PebblePreferences.extract(phone_root) do
      {:ok, schema} when is_map(schema) -> true
      _ -> false
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
