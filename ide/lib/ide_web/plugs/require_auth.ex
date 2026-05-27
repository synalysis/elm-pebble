defmodule IdeWeb.Plugs.RequireAuth do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Ide.Auth

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if Auth.public_mode?() and is_nil(conn.assigns[:current_user]) do
      if websocket_upgrade?(conn) do
        require Logger

        Logger.warning(
          "websocket rejected (not logged in) path=#{conn.request_path} host=#{conn.host}"
        )
      end

      conn
      |> reject()
      |> halt()
    else
      conn
    end
  end

  defp reject(conn) do
    if websocket_upgrade?(conn) do
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.text("Log in to use this endpoint.")
    else
      reject_non_websocket(conn)
    end
  end

  defp reject_non_websocket(conn) do
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
    not websocket_upgrade?(conn) and
      (String.starts_with?(conn.request_path, "/api/") or
         Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json")))
  end

  defp websocket_upgrade?(conn) do
    conn.method == "GET" and
      Enum.any?(get_req_header(conn, "upgrade"), fn value ->
        value |> String.downcase() |> String.contains?("websocket")
      end)
  end
end
