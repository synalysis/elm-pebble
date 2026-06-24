defmodule IdeWeb.SpeakerSampleController do
  use IdeWeb, :controller

  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.Types

  @allowed_extensions ~w(.pcm .raw .bin)

  @spec show(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug, "name" => name}) do
    with %Project{} = project <- Projects.get_project_by_slug(slug, conn.assigns.current_user),
         {:ok, filename} <- normalize_filename(name),
         path = sample_path(project, filename),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_file(200, path)
    else
      _ ->
        conn |> put_status(404) |> text("not found")
    end
  end

  @spec normalize_filename(String.t()) :: {:ok, String.t()} | :error
  defp normalize_filename(name) when is_binary(name) do
    basename = Path.basename(name)
    ext = Path.extname(basename) |> String.downcase()

    if basename != "" and ext in @allowed_extensions and basename == name do
      {:ok, basename}
    else
      :error
    end
  end

  defp normalize_filename(_), do: :error

  @spec sample_path(Project.t(), String.t()) :: String.t()
  defp sample_path(project, filename) do
    Path.join([
      Projects.project_workspace_path(project),
      "watch/resources/speaker_samples",
      filename
    ])
  end
end
