defmodule IdeWeb.Plugs.RemoteIp do
  @moduledoc """
  Rewrites `conn.remote_ip` from `X-Forwarded-For` / `X-Real-IP` when trusted.

  Enable with `IDE_TRUST_X_FORWARDED_FOR=1` (on by default in production).
  Only do this behind a reverse proxy that overwrites those headers.
  """

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if trust?() do
      rewrite(conn)
    else
      conn
    end
  end

  @spec trust?() :: boolean()
  def trust? do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:trust, false)
  end

  @spec rewrite(Plug.Conn.t()) :: Plug.Conn.t()
  defp rewrite(conn) do
    case forwarded_ip(conn) do
      nil ->
        conn

      ip ->
        %{conn | remote_ip: ip}
    end
  end

  @spec forwarded_ip(Plug.Conn.t()) :: :inet.ip_address() | nil
  defp forwarded_ip(conn) do
    conn
    |> forwarded_header()
    |> parse_ip()
  end

  @spec forwarded_header(Plug.Conn.t()) :: String.t() | nil
  defp forwarded_header(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] ->
        value
        |> String.split(",", trim: true)
        |> List.first()
        |> case do
          hop when is_binary(hop) -> String.trim(hop)
          _ -> nil
        end

      [] ->
        case Plug.Conn.get_req_header(conn, "x-real-ip") do
          [value | _] -> String.trim(value)
          _ -> nil
        end
    end
  end

  @spec parse_ip(String.t() | nil) :: :inet.ip_address() | nil
  defp parse_ip(nil), do: nil

  defp parse_ip(value) when is_binary(value) do
    trimmed =
      value
      |> String.trim()
      |> String.trim_leading("[")
      |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(trimmed)) do
      {:ok, ip} -> ip
      {:error, :einval} -> nil
    end
  end
end
