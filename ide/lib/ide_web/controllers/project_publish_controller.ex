defmodule IdeWeb.ProjectPublishController do
  @moduledoc """
  Serves prepared publish artifacts (PBW download) for authenticated projects.
  """
  use IdeWeb, :controller

  alias Ide.Projects
  alias IdeWeb.Types

  @spec pbw(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def pbw(conn, %{"slug" => slug}) do
    project = Projects.get_project_by_slug(slug, conn.assigns.current_user)

    cond do
      is_nil(project) ->
        conn |> put_status(:not_found) |> text("Project not found")

      true ->
        case Projects.latest_pbw_path(project) do
          {:ok, path} ->
            filename = Projects.pbw_download_filename(project)

            send_download(conn, {:file, path},
              filename: filename,
              content_type: "application/octet-stream"
            )

          {:error, :pbw_not_found} ->
            conn
            |> put_flash(:error, "No PBW found. Run Prepare Release first.")
            |> redirect(to: ~p"/projects/#{slug}/publish")
        end
    end
  end
end
