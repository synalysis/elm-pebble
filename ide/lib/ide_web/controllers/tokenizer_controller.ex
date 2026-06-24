defmodule IdeWeb.TokenizerController do
  use IdeWeb, :controller

  alias Ide.Tokenizer
  alias IdeWeb.Types

  @spec create(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
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
