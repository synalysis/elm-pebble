defmodule IdeWeb.Plugs.LogEmulatorWebSocket do
  @moduledoc false

  import Plug.Conn

  require Logger

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: path} = conn, _opts) when is_binary(path) do
    if emulator_ws_path?(path) do
      Logger.info(
        "emulator websocket request path=#{path} method=#{conn.method} upgrade=#{upgrade_request?(conn)} host=#{header(conn, "host")} origin=#{header(conn, "origin")}"
      )
    end

    conn
  end

  defp emulator_ws_path?(path) do
    String.starts_with?(path, "/api/emulator/") and
      (String.ends_with?(path, "/ws/vnc") or String.ends_with?(path, "/ws/phone"))
  end

  defp upgrade_request?(conn) do
    conn.method == "GET" and
      Enum.any?(get_req_header(conn, "upgrade"), fn value ->
        value |> String.downcase() |> String.contains?("websocket")
      end)
  end

  defp header(conn, name), do: conn |> get_req_header(name) |> List.first() |> Kernel.||("-")
end
