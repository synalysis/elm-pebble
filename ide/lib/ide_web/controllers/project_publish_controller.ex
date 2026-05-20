defmodule IdeWeb.ProjectPublishController do
  @moduledoc """
  Serves prepared publish artifacts in `public_custom` mode.
  """
  use IdeWeb, :controller

  alias Ide.Projects

  @spec pbw(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def pbw(conn, %{"slug" => slug}) do
    project = Projects.get_project_by_slug(slug, conn.assigns.current_user)

    cond do
      is_nil(project) ->
        conn |> put_status(:not_found) |> text("Project not found")

      true ->
        case Projects.latest_pbw_path(project) do
          {:ok, path} ->
            filename = Projects.pbw_download_filename(project)

            conn
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_download({:file, path}, content_type: "application/octet-stream")

          {:error, :pbw_not_found} ->
            conn
            |> put_flash(:error, "No PBW found. Run Prepare Release first.")
            |> redirect(to: ~p"/projects/#{slug}/publish")
        end
    end
  end
end
