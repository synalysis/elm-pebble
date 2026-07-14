defmodule Elmc.Backend.Wasm.StdlibImports do
  @moduledoc """
  Phase 3 web stdlib import names for `elm/http`, `elm/json`, and related packages.
  """

  @web_imports %{
    http_get: "web.http_get",
    http_post: "web.http_post",
    http_expect_json: "web.http_expect_json",
    json_decode: "web.json_decode",
    json_encode: "web.json_encode",
    url_parse: "web.url_parse",
    time_now: "web.time_now",
    svg_node: "web.svg_node",
    bytes_from_list: "web.bytes_from_list",
    navigation_push: "web.navigation_push",
    navigation_replace: "web.navigation_replace"
  }

  @spec import_name(atom()) :: String.t()
  def import_name(id) when is_atom(id) do
    Map.get(@web_imports, id, "web." <> Atom.to_string(id))
  end

  @spec all_imports() :: [{atom(), String.t()}]
  def all_imports, do: Map.to_list(@web_imports)
end
