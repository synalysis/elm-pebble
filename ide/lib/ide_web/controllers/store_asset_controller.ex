defmodule IdeWeb.StoreAssetController do
  use IdeWeb, :controller

  alias Ide.Projects
  alias Ide.StoreAssets

  @allowed_assets MapSet.new([StoreAssets.public_path(:icon_small), StoreAssets.public_path(:icon_large)])

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug, "name" => name}) do
    with true <- MapSet.member?(@allowed_assets, name),
         %{} = project <- Projects.get_project_by_slug(slug, conn.assigns.current_user),
         path = Path.join(StoreAssets.root_path(Projects.project_workspace_path(project)), name),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/png")
      |> send_file(200, path)
    else
      _ ->
        conn |> put_status(404) |> text("not found")
    end
  end
end
