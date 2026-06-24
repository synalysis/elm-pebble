defmodule IdeWeb.PageController do
  use IdeWeb, :controller

  alias IdeWeb.Types

  @spec home(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def home(conn, _params) do
    redirect(conn, to: ~p"/projects")
  end
end
