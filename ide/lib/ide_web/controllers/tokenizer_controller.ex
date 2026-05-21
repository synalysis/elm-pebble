defmodule IdeWeb.TokenizerController do
  use IdeWeb, :controller

  alias Ide.Tokenizer

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"source" => source}) when is_binary(source) do
    result = Tokenizer.tokenize(source)
    json(conn, result)
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Expected JSON body with `source` string."})
  end
end
