defmodule Elmc.Backend.Wasm.WebCoverageTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.WebCoverage

  test "BackendTask.Http stays reachable on web builds" do
    refute WebCoverage.server_only?({"BackendTask.Http", "getJson"})
    refute WebCoverage.server_only?({"BackendTask.Http", "request"})
    refute WebCoverage.server_only?({"BackendTask.Http", "post"})
    refute WebCoverage.server_only?({"BackendTask.Http", "withMetadata"})
  end

  test "other BackendTask modules remain server-only" do
    assert WebCoverage.server_only?({"BackendTask.File", "jsonFile"})
    assert WebCoverage.server_only?({"BackendTask.Glob", "fromString"})
    assert WebCoverage.server_only?({"BackendTask.Http", "requestRawUnchecked"})
  end
end
