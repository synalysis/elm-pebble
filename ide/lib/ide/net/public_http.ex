defmodule Ide.Net.PublicHttp do
  @moduledoc """
  Allows only http(s) URLs that resolve to public unicast addresses.

  Used by the debugger HTTP executor so Elm `Http` commands cannot reach
  loopback, link-local, or private networks (including cloud metadata).
  """

  @blocked_hosts MapSet.new([
                   "localhost",
                   "localhost.localdomain",
                   "metadata.google.internal",
                   "metadata.goog",
                   "kubernetes",
                   "kubernetes.default",
                   "kubernetes.default.svc"
                 ])

  @blocked_suffixes [".local", ".localhost", ".internal", ".home.arpa", ".lan"]

  @type url_error :: :invalid_url | :blocked_url

  @spec validate_url(String.t()) :: :ok | {:error, url_error()}
  def validate_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    with :ok <- validate_scheme(uri.scheme),
         :ok <- validate_userinfo(uri),
         {:ok, host} <- validate_host(uri.host),
         :ok <- validate_resolved_addresses(host) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  def validate_url(_), do: {:error, :invalid_url}

  @spec allowed_method(String.t() | atom() | nil) :: {:ok, atom()} | {:error, :invalid_method}
  def allowed_method(method) do
    normalized =
      method
      |> to_string()
      |> String.trim()
      |> String.downcase()

    case normalized do
      "get" -> {:ok, :get}
      "post" -> {:ok, :post}
      "put" -> {:ok, :put}
      "patch" -> {:ok, :patch}
      "delete" -> {:ok, :delete}
      "head" -> {:ok, :head}
      "options" -> {:ok, :options}
      _ -> {:error, :invalid_method}
    end
  end

  @spec validate_scheme(String.t() | nil) :: :ok | {:error, url_error()}
  defp validate_scheme(scheme) when scheme in ["http", "https"], do: :ok
  defp validate_scheme(_), do: {:error, :invalid_url}

  @spec validate_userinfo(URI.t()) :: :ok | {:error, url_error()}
  defp validate_userinfo(%URI{userinfo: userinfo}) when is_binary(userinfo) and userinfo != "",
    do: {:error, :blocked_url}

  defp validate_userinfo(_), do: :ok

  @spec validate_host(String.t() | nil) :: {:ok, String.t()} | {:error, url_error()}
  defp validate_host(host) when is_binary(host) do
    host = host |> String.trim() |> String.downcase() |> String.trim_trailing(".")

    cond do
      host == "" ->
        {:error, :invalid_url}

      MapSet.member?(@blocked_hosts, host) ->
        {:error, :blocked_url}

      Enum.any?(@blocked_suffixes, &String.ends_with?(host, &1)) ->
        {:error, :blocked_url}

      true ->
        {:ok, host}
    end
  end

  defp validate_host(_), do: {:error, :invalid_url}

  @spec validate_resolved_addresses(String.t()) :: :ok | {:error, url_error()}
  defp validate_resolved_addresses(host) do
    case ip_literal(host) do
      {:ok, ip} ->
        if blocked_ip?(ip), do: {:error, :blocked_url}, else: :ok

      :error ->
        case resolve_host(host) do
          [] ->
            {:error, :blocked_url}

          addrs ->
            if Enum.any?(addrs, &blocked_ip?/1), do: {:error, :blocked_url}, else: :ok
        end
    end
  end

  @spec ip_literal(String.t()) :: {:ok, :inet.ip_address()} | :error
  defp ip_literal(host) do
    trimmed =
      host
      |> String.trim_leading("[")
      |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(trimmed)) do
      {:ok, ip} -> {:ok, ip}
      {:error, :einval} -> :error
    end
  end

  @spec resolve_host(String.t()) :: [:inet.ip_address()]
  defp resolve_host(host) do
    charlist = String.to_charlist(host)

    ipv4 =
      case :inet.getaddrs(charlist, :inet) do
        {:ok, addrs} -> addrs
        {:error, _} -> []
      end

    ipv6 =
      case :inet.getaddrs(charlist, :inet6) do
        {:ok, addrs} -> addrs
        {:error, _} -> []
      end

    ipv4 ++ ipv6
  end

  @spec blocked_ip?(:inet.ip_address()) :: boolean()
  def blocked_ip?({a, b, c, d})
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    cond do
      a == 0 -> true
      a == 10 -> true
      a == 127 -> true
      a == 169 and b == 254 -> true
      a == 172 and b >= 16 and b <= 31 -> true
      a == 192 and b == 0 and c == 0 -> true
      a == 192 and b == 168 -> true
      a == 100 and b >= 64 and b <= 127 -> true
      a == 198 and b in [18, 19] -> true
      a >= 224 -> true
      true -> false
    end
  end

  def blocked_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def blocked_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true

  def blocked_ip?({a, b, c, d, e, f, g, h})
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
             is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) do
    cond do
      a == 0xFE80 -> true
      a == 0xFEC0 -> true
      Bitwise.band(a, 0xFE00) == 0xFC00 -> true
      a == 0x2001 and b == 0x0DB8 -> true
      a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0xFFFF ->
        blocked_ip?({Bitwise.bsr(g, 8), Bitwise.band(g, 0xFF), Bitwise.bsr(h, 8), Bitwise.band(h, 0xFF)})

      a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0 ->
        blocked_ip?({0, 0, Bitwise.bsr(h, 8), Bitwise.band(h, 0xFF)})

      true ->
        false
    end
  end

  def blocked_ip?(_), do: true
end
