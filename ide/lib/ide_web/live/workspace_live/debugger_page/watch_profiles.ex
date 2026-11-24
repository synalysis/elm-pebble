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
  def selected_id(%{watch_profile_id: watch_profile_id}, project)
      when is_binary(watch_profile_id) do
    normalize_id(watch_profile_id, project)
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
    normalize_id(Map.get(settings, "watch_profile_id"), project)
  end

  def project_id(_), do: default_id()

  @spec normalize_id(wire_input(), Project.t() | nil) :: String.t()
  def normalize_id(value, project \\ nil)

  def normalize_id(value, project) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    allowed = allowed_ids(project)
    if normalized in allowed, do: normalized, else: default_id(project)
  end

  def normalize_id(_, project), do: default_id(project)

  defp allowed_ids(project) do
    if Ide.DeviceFamily.handheld?(project) do
      Ide.Handheld.Models.ordered_ids()
    else
      profile_ids()
    end
  end

  @spec profile_ids() :: [String.t()]
  def profile_ids do
    Debugger.watch_profiles()
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.filter(&is_binary/1)
  end

  @spec default_id(Project.t() | nil) :: String.t()
  def default_id(project \\ nil) do
    if Ide.DeviceFamily.handheld?(project) do
      Ide.Handheld.Models.default_id()
    else
      profile_ids()
      |> List.first()
      |> case do
        id when is_binary(id) -> id
        _ -> "basalt"
      end
    end
  end
end
