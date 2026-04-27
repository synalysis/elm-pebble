defmodule Ide.Acp.McpServersTest do
  use ExUnit.Case, async: true

  alias Ide.Acp.McpServers

  test "builds stdio config for the IDE MCP server" do
    config =
      McpServers.ide_stdio(
        capabilities: [:read, :edit, :build, :unknown],
        ide_dir: "/tmp/elm pebble/ide",
        env: %{"TOKEN" => "redacted"}
      )

    assert config["name"] == "elm-pebble-ide"
    assert String.ends_with?(config["command"], "bash")
    assert ["-lc", command] = config["args"]
    assert command =~ "cd '/tmp/elm pebble/ide'"
    assert command =~ "mix ide.mcp --capabilities 'read,edit,build'"
    assert config["env"] == [%{"name" => "TOKEN", "value" => "redacted"}]
  end

  test "defaults invalid capability input to read-only" do
    config = McpServers.ide_stdio(capabilities: "publish,unknown", ide_dir: "/tmp/ide")

    assert ["-lc", command] = config["args"]
    assert command =~ "--capabilities 'read'"
  end
end
