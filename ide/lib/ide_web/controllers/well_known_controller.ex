defmodule IdeWeb.WellKnownController do
  use IdeWeb, :controller

  @doc """
  Answers MCP OAuth protected-resource discovery probes (RFC 9728).

  This IDE MCP HTTP endpoint does not use OAuth. Cursor and other clients still
  probe `/.well-known/oauth-protected-resource` before connecting; return a clean
  JSON 404 so discovery fails without the Phoenix HTML debugger page.
  """
  @spec oauth_protected_resource(Plug.Conn.t(), map()) :: Plug.Conn.t()

  def oauth_protected_resource(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:not_found)
    |> json(%{
      "error" => "not_found",
      "error_description" =>
        "This MCP endpoint does not publish OAuth protected resource metadata."
    })
  end
end
