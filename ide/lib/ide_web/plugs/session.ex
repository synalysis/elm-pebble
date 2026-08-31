defmodule IdeWeb.Plugs.Session do
  @moduledoc false

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    Plug.Session.call(conn, Plug.Session.init(IdeWeb.Session.options()))
  end
end
