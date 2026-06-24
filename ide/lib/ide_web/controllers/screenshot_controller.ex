defmodule IdeWeb.ScreenshotController do
  use IdeWeb, :controller

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Screenshots
  alias IdeWeb.Types

  @spec show(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug, "target" => target, "name" => name}) do
    with %{} = project <- Projects.get_project_by_slug(slug, conn.assigns.current_user),
         {:ok, emulator_target} <- Screenshots.normalize_emulator_target_public(target),
         {:ok, filename} <- Screenshots.normalize_filename_public(name),
         path = screenshot_path(project, emulator_target, filename),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(Screenshots.mime_type_for_path(path))
      |> send_file(200, path)
    else
      _ ->
        conn |> put_status(404) |> text("not found")
    end
  end

  @spec screenshot_path(Project.t(), String.t(), String.t()) :: String.t()
  defp screenshot_path(project, emulator_target, filename) do
    Path.join([Projects.screenshots_path(project), emulator_target, filename])
  end
end
