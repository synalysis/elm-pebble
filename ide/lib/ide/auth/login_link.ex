defmodule Ide.Auth.LoginLink do
  @moduledoc false

  @token_bytes 32

  @spec generate() :: {String.t(), String.t()}
  def generate do
    raw = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)
    {raw, hash_token(raw)}
  end

  @spec hash_token(String.t()) :: String.t()
  def hash_token(raw) when is_binary(raw) do
    :sha256
    |> :crypto.hash(raw)
    |> Base.url_encode64(padding: false)
  end

  @spec verify_url(String.t()) :: String.t()
  def verify_url(raw_token) when is_binary(raw_token) do
    IdeWeb.Endpoint.url() <> "/auth/email/verify?" <> URI.encode_query(token: raw_token)
  end
end
