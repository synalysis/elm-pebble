defmodule IdeWeb.Plugs.CanonicalLoopbackHost do
  @moduledoc """
  Sends browser navigations from `127.0.0.1` / `::1` to `localhost`.

  Firebase Auth authorizes `localhost` but not loopback IPs, so CloudPebble
  login fails when the IDE is opened as `http://127.0.0.1:4000`. Public
  deployments already use a hostname. This keeps local mode on the same
  authorized origin without touching API/MCP clients that use `127.0.0.1`.
  """

  import Plug.Conn

  @loopback_hosts MapSet.new(["127.0.0.1", "::1", "[::1]"])

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    host = conn.host || ""

    if MapSet.member?(@loopback_hosts, host) and browser_navigation?(conn) do
      conn
      |> put_resp_header("location", localhost_url(conn))
      |> send_resp(302, "")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  @spec browser_navigation?(Plug.Conn.t()) :: boolean()
  defp browser_navigation?(conn) do
    accept = conn |> get_req_header("accept") |> List.first() || ""
    String.contains?(accept, "text/html")
  end

  @spec localhost_url(Plug.Conn.t()) :: String.t()
  defp localhost_url(conn) do
    port = conn.port
    scheme = conn.scheme || :http
    path = conn.request_path || "/"
    query = conn.query_string || ""

    uri = %URI{
      scheme: Atom.to_string(scheme),
      host: "localhost",
      path: path,
      query: if(query == "", do: nil, else: query)
    }

    uri
    |> maybe_put_port(scheme, port)
    |> URI.to_string()
  end

  @spec maybe_put_port(URI.t(), atom(), integer() | nil) :: URI.t()
  defp maybe_put_port(uri, :https, port) when port in [443, nil], do: uri
  defp maybe_put_port(uri, :http, port) when port in [80, nil], do: uri
  defp maybe_put_port(uri, _scheme, port) when is_integer(port), do: %{uri | port: port}
  defp maybe_put_port(uri, _scheme, _port), do: uri
end
