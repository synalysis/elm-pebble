defmodule IdeWeb.Plugs.RequireAuth do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Ide.Auth

  @spec init(term()) :: term()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if Auth.public_mode?() and is_nil(conn.assigns[:current_user]) do
      conn
      |> reject()
      |> halt()
    else
      conn
    end
  end

  defp reject(conn) do
    if json_request?(conn) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Log in to use this endpoint."})
    else
      conn
      |> put_flash(:error, "Log in to create and manage projects.")
      |> redirect(to: "/login")
    end
  end

  defp json_request?(conn) do
    String.starts_with?(conn.request_path, "/api/") or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))
  end
end
