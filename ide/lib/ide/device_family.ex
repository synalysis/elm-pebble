defmodule Ide.DeviceFamily do
  @moduledoc """
  IDE-only grouping for which pages and device lists to show.

  The compiler does not read this. It follows the selected device id.
  Handheld devices currently have no emulator, so that page stays hidden.
  """

  alias Ide.EmulatorSupport
  alias Ide.Handheld.Models
  alias Ide.Projects.Project
  alias Ide.WatchModels

  @spec family(Project.t() | nil) :: String.t()
  def family(project), do: family(project, System.get_env("IDE_DEVICE_FAMILY"))

  @doc """
  `IDE_DEVICE_FAMILY` is the IDE session switch used by
  `start-ide-local-handheld.sh`. The compiler does not read it.
  """
  @spec family(Project.t() | nil, String.t() | nil) :: String.t()
  def family(%Project{} = project, override) do
    case session_family(override) do
      family when is_binary(family) ->
        family

      _ ->
        project.release_defaults
        |> Kernel.||(%{})
        |> Map.get("device_family")
        |> normalize_family()
    end
  end

  def family(_, override), do: session_family(override) || "pebble"

  @spec normalize_family(term()) :: String.t()
  def normalize_family("handheld"), do: "handheld"
  def normalize_family(_), do: "pebble"

  defp session_family("handheld"), do: "handheld"
  defp session_family("pebble"), do: "pebble"
  defp session_family(_), do: nil

  @spec handheld?(Project.t() | nil) :: boolean()
  def handheld?(project), do: family(project) == "handheld"

  @doc """
  True when the IDE should show the Emulator page for this project.
  """
  @spec emulator_page?(Project.t() | nil) :: boolean()
  def emulator_page?(%Project{} = project) do
    if handheld?(project) do
      platforms =
        project.release_defaults
        |> Kernel.||(%{})
        |> Map.get("target_platforms", Models.ordered_ids())

      Enum.any?(List.wrap(platforms), &Models.emulator?/1)
    else
      true
    end
  end

  def emulator_page?(_), do: true

  @spec ordered_ids(Project.t() | nil) :: [String.t()]
  def ordered_ids(project) do
    if handheld?(project), do: Models.ordered_ids(), else: WatchModels.ordered_ids()
  end

  @spec emulator_target_ids(Project.t() | nil) :: [String.t()]
  def emulator_target_ids(project) do
    if handheld?(project), do: Models.ordered_ids(), else: EmulatorSupport.supported_targets()
  end

  @spec default_id(Project.t() | nil) :: String.t()
  def default_id(project) do
    if handheld?(project), do: Models.default_id(), else: WatchModels.default_id()
  end

  @spec default_platforms(String.t()) :: [String.t()]
  def default_platforms("handheld"), do: Models.ordered_ids()
  def default_platforms(_), do: WatchModels.ordered_ids()

  @spec normalize_id(Project.t() | nil, term()) :: String.t()
  def normalize_id(project, id) do
    if handheld?(project) do
      Models.normalize(id)
    else
      EmulatorSupport.normalize_target(id)
    end
  end

  @spec picker_label(Project.t() | nil) :: String.t()
  def picker_label(project) do
    if handheld?(project), do: "Handheld type", else: "Watch model / emulator target"
  end

  @spec select_options(Project.t() | nil) :: [{String.t(), String.t()}] | [String.t()]
  def select_options(project) do
    if handheld?(project) do
      Enum.map(Models.list_items(), fn item -> {item["label"], item["id"]} end)
    else
      emulator_target_ids(project)
    end
  end

  @doc """
  IDE frame size. Handheld ids use the handheld catalog. Everything else
  stays a watch profile.
  """
  @spec preview_screen(String.t() | nil) :: {pos_integer(), pos_integer(), boolean()}
  def preview_screen(id) do
    if Models.known?(id) do
      Models.preview_screen(id)
    else
      screen = id |> WatchModels.profile_for() |> WatchModels.profile_screen()
      {Map.get(screen, "width", 144), Map.get(screen, "height", 168), false}
    end
  end
end
