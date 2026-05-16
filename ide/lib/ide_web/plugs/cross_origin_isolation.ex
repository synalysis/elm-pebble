defmodule IdeWeb.Plugs.CrossOriginIsolation do
  @moduledoc false

  import Plug.Conn

  @spec init(term()) :: term()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    if isolated_path?(path) do
      conn
      |> put_resp_header("cross-origin-opener-policy", "same-origin")
      |> put_resp_header("cross-origin-embedder-policy", "require-corp")
      |> put_resp_header("cross-origin-resource-policy", "same-origin")
    else
      conn
    end
  end

  defp isolated_path?("/wasm-emulator" <> _), do: true
  defp isolated_path?("/api/wasm-emulator" <> _), do: true

  defp isolated_path?(path) when is_binary(path) do
    String.starts_with?(path, "/projects/") and String.ends_with?(path, "/emulator")
  end
end
