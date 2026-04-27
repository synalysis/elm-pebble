defmodule IdeWeb.PageController do
  use IdeWeb, :controller

  @spec home(term(), term()) :: term()
  def home(conn, _params) do
    redirect(conn, to: ~p"/projects")
  end
end
