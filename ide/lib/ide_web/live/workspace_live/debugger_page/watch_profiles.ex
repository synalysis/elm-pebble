defmodule IdeWeb.WorkspaceLive.DebuggerPage.WatchProfiles do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerPage.Assigns
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type assigns :: Assigns.t()
  @type wire_input :: SupportTypes.wire_value()

  @type debugger_state :: SupportTypes.debugger_state_map()

  @spec selected_id(assigns(), debugger_state() | nil) :: String.t()
  def selected_id(%{watch_profile_id: watch_profile_id}, _project)
      when is_binary(watch_profile_id) do
    normalize_id(watch_profile_id)
  end

  def selected_id(_debugger_state, project), do: project_id(project)

  @spec state_id(debugger_state(), Project.t() | nil) :: String.t() | nil
  def state_id(%{} = state, project) do
    case Map.get(state, :watch_profile_id) do
      nil -> selected_id(state, project)
      id -> id
    end
  end

  def state_id(_state, _project), do: nil

  @spec project_id(Project.t() | nil) :: String.t()
  def project_id(%Project{} = project) do
    settings = project.debugger_settings || %{}
    normalize_id(Map.get(settings, "watch_profile_id"))
  end

  def project_id(_), do: default_id()

  @spec normalize_id(wire_input()) :: String.t()
  def normalize_id(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in profile_ids(), do: normalized, else: default_id()
  end

  def normalize_id(_), do: default_id()

  @spec profile_ids() :: [String.t()]
  def profile_ids do
    Debugger.watch_profiles()
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.filter(&is_binary/1)
  end

  @spec default_id() :: String.t()
  def default_id do
    profile_ids()
    |> List.first()
    |> case do
      id when is_binary(id) -> id
      _ -> "basalt"
    end
  end
end
