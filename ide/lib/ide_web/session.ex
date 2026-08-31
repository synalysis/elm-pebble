defmodule IdeWeb.Session do
  @moduledoc """
  Shared cookie-session options for Plug.Session and Phoenix sockets.
  """

  @signing_salt "vNWvO1xq"

  @spec options() :: keyword()
  def options do
    [
      store: :cookie,
      key: "_ide_key",
      signing_salt: @signing_salt,
      same_site: "Lax",
      http_only: true,
      secure: secure?()
    ]
  end

  @spec secure?() :: boolean()
  def secure? do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:secure, false)
  end
end
