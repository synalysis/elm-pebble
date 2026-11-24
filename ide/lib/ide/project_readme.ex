defmodule Ide.ProjectReadme do
  @moduledoc """
  Generates the workspace `README.md` that explains an Elm Pebble project and links to the IDE.
  """

  alias Ide.Projects.Project

  @site_url "https://elm-pebble.dev"
  @marker_start "<!-- elm-pebble-ide:readme -->"
  @marker_end "<!-- /elm-pebble-ide:readme -->"

  @type readme_error :: File.posix()

  @spec site_url() :: String.t()
  def site_url, do: @site_url

  @spec content(Project.t()) :: String.t()
  def content(%Project{} = project) do
    name = project.name || "Elm Pebble project"
    kind = target_kind(project.target_type)
    description = project_description(project)
    handheld? = Ide.DeviceFamily.handheld?(project)

    """
    #{@marker_start}
    # #{name}

    #{description_block(description)}

    #{intro(handheld?, kind)}

    ## Develop

    Open the project in the IDE to edit the Elm source.

    **#{@site_url}**

    ## Repository layout

    #{layout(handheld?)}

    #{@marker_end}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  @doc """
  Writes or updates `README.md` under `workspace_root`.

  Replaces only the marked IDE block when the file already exists; creates the file when missing.
  """
  @spec write(String.t(), Project.t()) :: :ok | {:error, readme_error()}
  def write(workspace_root, %Project{} = project) when is_binary(workspace_root) do
    path = Path.join(workspace_root, "README.md")
    body = content(project)

    merged =
      case File.read(path) do
        {:ok, existing} -> merge_marked_block(existing, body)
        {:error, :enoent} -> body
        {:error, reason} -> {:error, reason}
      end

    case merged do
      {:error, _} = error ->
        error

      text ->
        case File.write(path, text) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec merge_marked_block(String.t(), String.t()) :: String.t()
  defp merge_marked_block(existing, generated) do
    if String.contains?(existing, @marker_start) and String.contains?(existing, @marker_end) do
      Regex.replace(
        ~r/<!-- elm-pebble-ide:readme -->.*?<!-- \/elm-pebble-ide:readme -->/s,
        existing,
        String.trim(generated),
        global: false
      )
    else
      generated
    end
  end

  defp intro(true, _kind) do
    "This repository contains a handheld Elm app for MeowKit or Flipper. It has one program and no companion app or protocol interface."
  end

  defp intro(false, kind) do
    "This repository contains an **Elm Pebble** #{kind} created in the [Elm Pebble IDE](#{@site_url})."
  end

  defp layout(true) do
    """
    | Path | Purpose |
    |------|---------|
    | `app/src/` | Handheld Elm application |

    Hardware examples (USB, NFC, infrared, GPIO, radio, vibes, battery) live in `Handheld.*`.
    """
  end

  defp layout(false) do
    """
    | Path | Purpose |
    |------|---------|
    | `src/` | Watch (and related) Elm application source |
    | `protocol/`, `phone/` | Companion protocol and phone app (when present) |
    | `screenshots/` | Emulator screenshots for App Store listings (per watch platform) |
    | `store_assets/` | App Store listing icons configured in Project Settings |

    Build artifacts and the local Pebble SDK tree (`.pebble-sdk/`) are not committed to Git; they are reproduced when you build from the IDE.
    """
  end

  @spec target_kind(String.t() | nil) :: String.t()
  defp target_kind("watchface"), do: "watchface"
  defp target_kind("companion"), do: "companion phone app"
  defp target_kind(_), do: "watch app"

  @spec project_description(Project.t()) :: String.t()
  defp project_description(%Project{release_defaults: defaults}) when is_map(defaults) do
    defaults
    |> Map.get("description", "")
    |> to_string()
    |> String.trim()
  end

  defp project_description(_), do: ""

  @spec description_block(String.t()) :: String.t()
  defp description_block(""), do: ""
  defp description_block(description), do: "#{description}\n"
end
