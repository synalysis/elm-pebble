defmodule IdeWeb.PageController do
  use IdeWeb, :controller

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    redirect(conn, to: ~p"/projects")
  end
end
