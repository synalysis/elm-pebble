defmodule Ide.SimulatorCapabilities do
  @moduledoc """
  Infers which simulator settings are relevant for a project's watch and companion APIs.
  """

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.SimulatorCapabilities.Detect

  @doc """
  Returns a set of capability keys used to filter simulator settings UI and persistence.
  """
  @spec infer(Project.t() | nil, map() | nil) :: MapSet.t(String.t())
  def infer(project \\ nil, debugger_state \\ nil)

  def infer(%Project{} = project, debugger_state) do
    watch = introspect_for(project, debugger_state, :watch)
    phone = introspect_for(project, debugger_state, :phone)
    companion = introspect_for(project, debugger_state, :companion)

    caps_from_introspect(watch, phone, companion)
  end

  def infer(nil, debugger_state) when is_map(debugger_state) do
    watch = runtime_introspect(debugger_state, :watch)
    phone = runtime_introspect(debugger_state, :phone)
    companion = runtime_introspect(debugger_state, :companion)
    caps_from_introspect(watch, phone, companion)
  end

  def infer(_project, _debugger_state), do: MapSet.new()

  @spec caps_from_introspect(map() | nil, map() | nil, map() | nil) :: MapSet.t(String.t())
  defp caps_from_introspect(watch, phone, companion) do
    MapSet.new()
    |> MapSet.union(Detect.watch_caps(watch))
    |> MapSet.union(Detect.phone_caps(phone))
    |> MapSet.union(Detect.companion_caps(companion))
  end

  @doc """
  Emulator-only controls that are not driven by Elm API usage.
  """
  @spec emulator_only_caps() :: MapSet.t(String.t())
  def emulator_only_caps, do: MapSet.new(["emulator_timeline_peek"])

  @spec introspect_for(Project.t(), map() | nil, :watch | :phone | :companion) ::
          map() | nil
  defp introspect_for(%Project{} = project, debugger_state, surface) do
    case runtime_introspect(debugger_state, surface) do
      %{} = introspect ->
        introspect

      _ ->
        project |> workspace_root() |> workspace_introspect(surface)
    end
  end

  @spec runtime_introspect(map(), :watch | :phone | :companion) :: map() | nil
  defp runtime_introspect(%{watch: watch} = _state, :watch) when is_map(watch),
    do: model_introspect(watch)

  defp runtime_introspect(%{"watch" => watch} = _state, :watch) when is_map(watch),
    do: model_introspect(watch)

  defp runtime_introspect(%{phone: phone} = _state, :phone) when is_map(phone),
    do: model_introspect(phone)

  defp runtime_introspect(%{"phone" => phone} = _state, :phone) when is_map(phone),
    do: model_introspect(phone)

  defp runtime_introspect(%{companion: companion} = _state, :companion) when is_map(companion),
    do: model_introspect(companion)

  defp runtime_introspect(%{"companion" => companion} = _state, :companion) when is_map(companion),
    do: model_introspect(companion)

  defp runtime_introspect(%{simulator_settings: _} = state, :watch),
    do: runtime_introspect(Map.drop(state, [:simulator_settings]), :watch)

  defp runtime_introspect(_state, _surface), do: nil

  @spec model_introspect(map()) :: map() | nil
  defp model_introspect(%{"model" => _} = surface) when is_map(surface),
    do: RuntimeArtifacts.introspect(surface)

  defp model_introspect(%{model: _} = surface) when is_map(surface),
    do: RuntimeArtifacts.introspect(surface)

  defp model_introspect(%{"shell" => _} = surface) when is_map(surface),
    do: RuntimeArtifacts.introspect(surface)

  defp model_introspect(%{shell: _} = surface) when is_map(surface),
    do: RuntimeArtifacts.introspect(surface)

  defp model_introspect(model) when is_map(model), do: RuntimeArtifacts.introspect(model)

  @spec workspace_root(Project.t()) :: String.t() | nil
  defp workspace_root(%Project{} = project) do
    root = Projects.project_workspace_path(project)
    if File.dir?(root), do: root, else: nil
  end

  @spec workspace_introspect(String.t() | nil, :watch | :phone | :companion) :: map() | nil
  defp workspace_introspect(nil, _surface), do: nil

  defp workspace_introspect(workspace_root, surface) do
    source_root =
      case surface do
        :watch -> "watch"
        :phone -> "phone"
        :companion -> "phone"
      end

    workspace_root
    |> Path.join(source_root)
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> Enum.reduce(nil, fn path, acc ->
      with {:ok, content} <- File.read(path),
           {:ok, %{"debugger_contract" => introspect}} <-
             Ide.Debugger.CompileContract.analyze_source(content, Path.basename(path)) do
        merge_introspect(acc, introspect, surface)
      else
        _ -> acc
      end
    end)
  end

  @spec merge_introspect(map() | nil, map(), :watch | :phone | :companion) :: map()
  defp merge_introspect(nil, introspect, _surface), do: introspect

  defp merge_introspect(existing, introspect, surface) do
    merged_caps =
      case surface do
        :watch -> Detect.watch_caps(existing) |> MapSet.union(Detect.watch_caps(introspect))
        :phone -> Detect.phone_caps(existing) |> MapSet.union(Detect.phone_caps(introspect))
        :companion -> Detect.companion_caps(existing) |> MapSet.union(Detect.companion_caps(introspect))
      end

    if MapSet.equal?(merged_caps, MapSet.new()) do
      introspect
    else
      %{
        "imported_modules" =>
          Enum.uniq(
            List.wrap(Map.get(existing, "imported_modules")) ++
              List.wrap(Map.get(introspect, "imported_modules"))
          ),
        "subscription_calls" =>
          List.wrap(Map.get(existing, "subscription_calls")) ++
            List.wrap(Map.get(introspect, "subscription_calls")),
        "init_cmd_calls" =>
          List.wrap(Map.get(existing, "init_cmd_calls")) ++
            List.wrap(Map.get(introspect, "init_cmd_calls")),
        "update_cmd_calls" =>
          List.wrap(Map.get(existing, "update_cmd_calls")) ++
            List.wrap(Map.get(introspect, "update_cmd_calls")),
        "function_cmd_calls" => %{}
      }
    end
  end
end
