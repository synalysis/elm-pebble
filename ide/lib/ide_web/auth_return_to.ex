defmodule IdeWeb.AuthReturnTo do
  @moduledoc false

  @session_key :login_return_to
  @default "/projects"

  @spec session_key() :: atom()
  def session_key, do: @session_key

  @spec default() :: String.t()
  def default, do: @default

  @doc """
  Builds a same-origin path (+ query/fragment) from the current request.
  """
  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(%Plug.Conn{} = conn) do
    path = conn.request_path || @default

    query =
      case conn.query_string do
        qs when is_binary(qs) and qs != "" -> "?" <> qs
        _ -> ""
      end

    sanitize(path <> query)
  end

  @doc """
  Login URL that carries `return_to` as a query param.
  """
  @spec login_path(term()) :: String.t()
  def login_path(return_to) do
    "/login?return_to=" <> URI.encode_www_form(sanitize(return_to))
  end

  @spec put_session(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def put_session(conn, return_to) do
    Plug.Conn.put_session(conn, @session_key, sanitize(return_to))
  end

  @doc """
  Resolves return_to from params, then session, then default — without clearing session.
  """
  @spec peek(Plug.Conn.t(), map() | keyword() | nil) :: String.t()
  def peek(conn, params \\ nil) do
    from_params =
      cond do
        is_map(params) -> Map.get(params, "return_to") || Map.get(params, :return_to)
        true -> nil
      end

    from_params
    |> Kernel.||(Plug.Conn.get_session(conn, @session_key))
    |> sanitize()
  end

  @doc """
  Like `peek/2`, then drops the session key (call before `clear_session` if needed).
  """
  @spec take(Plug.Conn.t(), map() | keyword() | nil) :: {Plug.Conn.t(), String.t()}
  def take(conn, params \\ nil) do
    return_to = peek(conn, params)
    {Plug.Conn.delete_session(conn, @session_key), return_to}
  end

  @spec sanitize(term()) :: String.t()
  def sanitize(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" ->
        @default

      String.starts_with?(trimmed, "/") and not String.starts_with?(trimmed, "//") ->
        trimmed

      true ->
        case URI.parse(trimmed) do
          %URI{path: path} = uri when is_binary(path) and path != "" ->
            if same_site_return?(uri) do
              query = if is_binary(uri.query) and uri.query != "", do: "?#{uri.query}", else: ""

              fragment =
                if is_binary(uri.fragment) and uri.fragment != "", do: "##{uri.fragment}", else: ""

              path <> query <> fragment
            else
              @default
            end

          _ ->
            @default
        end
    end
  end

  def sanitize(_), do: @default

  defp same_site_return?(%URI{host: host, scheme: scheme}) do
    endpoint = IdeWeb.Endpoint.struct_url()
    host in [nil, endpoint.host] and scheme in [nil, endpoint.scheme, "http", "https"]
  end
end
