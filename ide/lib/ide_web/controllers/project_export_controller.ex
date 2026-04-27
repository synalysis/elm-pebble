defmodule IdeWeb.ProjectExportController do
  use IdeWeb, :controller

  alias Ide.Projects

  @spec show(term(), term()) :: term()
  def show(conn, %{"id" => id}) do
    project = Projects.get_project!(id)

    case Projects.export_project(project) do
      {:ok, zip_path} ->
        schedule_cleanup(zip_path)

        conn
        |> send_download({:file, zip_path},
          filename: "#{project.slug}.zip",
          content_type: "application/zip"
        )

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not export project: #{inspect(reason)}")
        |> redirect(to: ~p"/projects")
    end
  end

  # Delay deletion so the web server can finish streaming the file.
  @spec schedule_cleanup(term()) :: term()
  defp schedule_cleanup(zip_path) do
    Task.start(fn ->
      Process.sleep(60_000)
      _ = File.rm(zip_path)
    end)
  end
end
