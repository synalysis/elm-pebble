defmodule Ide.Auth.EmailHash do
  @moduledoc """
  Deterministic HMAC blind index for normalized email addresses.

  Stores a one-way lookup key in the database without persisting plaintext email.
  """

  alias Ide.Auth.User

  @spec hash(String.t()) :: String.t()
  def hash(email) when is_binary(email) do
    email = User.normalize_email(email)

    :crypto.mac(:hmac, :sha256, pepper(), email)
    |> Base.url_encode64(padding: false)
  end

  @spec pepper() :: binary()
  def pepper do
    Application.get_env(:ide, Ide.Auth, [])
    |> Keyword.get(:email_hash_pepper)
    |> case do
      pepper when is_binary(pepper) and pepper != "" ->
        pepper

      _ ->
        case Application.get_env(:ide, IdeWeb.Endpoint)[:secret_key_base] do
          secret when is_binary(secret) and secret != "" ->
            secret

          _ ->
            raise """
            email_hash_pepper is not configured.

            Set IDE_EMAIL_HASH_PEPPER or configure IdeWeb.Endpoint secret_key_base.
            """
        end
    end
  end
end
