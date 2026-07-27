defmodule Elmc.WasmStdlibImportsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.StdlibImports

  test "web stdlib imports use web namespace" do
    assert StdlibImports.import_name(:http_get) == "web.http_get"
    assert StdlibImports.import_name(:json_decode) == "web.json_decode"
    assert Enum.all?(StdlibImports.all_imports(), fn {_id, name} -> String.starts_with?(name, "web.") end)
  end
end
