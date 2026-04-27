defmodule Ide.Acp.ClientTest do
  use ExUnit.Case, async: true

  alias Ide.Acp.Client

  setup do
    python = System.find_executable("python3") || System.find_executable("python")
    assert is_binary(python)

    dir =
      Path.join(System.tmp_dir!(), "ide_acp_client_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, python: python, dir: dir}
  end

  test "initializes, creates a session, and receives prompt updates", %{python: python, dir: dir} do
    script = write_agent(dir, "agent.py", basic_agent_script())

    {:ok, client} = Client.start_link(command: python, args: [script], owner: self())

    assert {:ok, %{"protocolVersion" => 1, "agentCapabilities" => capabilities}} =
             Client.initialize(client)

    assert capabilities["loadSession"] == true

    assert {:ok, %{"sessionId" => "sess-1", "mcpServerCount" => 1}} =
             Client.new_ide_session(client, dir,
               ide_mcp: [capabilities: [:read, :edit], ide_dir: "/tmp/ide"]
             )

    assert {:ok, %{"stopReason" => "end_turn"}} = Client.prompt_text(client, "sess-1", "hello")

    assert_receive {:acp_notification, ^client, "session/update",
                    %{
                      "sessionId" => "sess-1",
                      "update" => %{
                        "sessionUpdate" => "agent_message_chunk",
                        "content" => %{"text" => "hello from fake agent"}
                      }
                    }}
  end

  test "answers permission requests conservatively", %{python: python, dir: dir} do
    script = write_agent(dir, "permission_agent.py", permission_agent_script())

    {:ok, client} = Client.start_link(command: python, args: [script], owner: self())

    assert {:ok, %{"protocolVersion" => 1}} = Client.initialize(client)
    assert {:ok, %{"sessionId" => "sess-1"}} = Client.new_session(client, dir)

    assert {:ok,
            %{
              "stopReason" => "end_turn",
              "permissionOutcome" => %{"outcome" => "selected", "optionId" => "reject-once"}
            }} = Client.prompt_text(client, "sess-1", "do the thing")
  end

  defp write_agent(dir, name, source) do
    path = Path.join(dir, name)
    File.write!(path, source)
    path
  end

  defp basic_agent_script do
    """
    import json
    import sys

    def send(message):
        print(json.dumps(message, separators=(",", ":")), flush=True)

    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params") or {}

        if method == "initialize":
            send({
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "protocolVersion": 1,
                    "agentCapabilities": {"loadSession": True},
                    "agentInfo": {"name": "fake-agent", "version": "0.0.1"},
                    "authMethods": []
                }
            })
        elif method == "session/new":
            send({
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "sessionId": "sess-1",
                    "mcpServerCount": len(params.get("mcpServers") or [])
                }
            })
        elif method == "session/prompt":
            send({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": params["sessionId"],
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": "hello from fake agent"}
                    }
                }
            })
            send({"jsonrpc": "2.0", "id": request_id, "result": {"stopReason": "end_turn"}})
    """
  end

  defp permission_agent_script do
    """
    import json
    import sys

    def send(message):
        print(json.dumps(message, separators=(",", ":")), flush=True)

    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        request_id = message.get("id")

        if method == "initialize":
            send({
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "protocolVersion": 1,
                    "agentCapabilities": {},
                    "agentInfo": {"name": "permission-agent", "version": "0.0.1"},
                    "authMethods": []
                }
            })
        elif method == "session/new":
            send({"jsonrpc": "2.0", "id": request_id, "result": {"sessionId": "sess-1"}})
        elif method == "session/prompt":
            send({
                "jsonrpc": "2.0",
                "id": 900,
                "method": "session/request_permission",
                "params": {
                    "sessionId": "sess-1",
                    "toolCall": {"toolCallId": "tool-1"},
                    "options": [
                        {"optionId": "allow-once", "name": "Allow once", "kind": "allow_once"},
                        {"optionId": "reject-once", "name": "Reject", "kind": "reject_once"}
                    ]
                }
            })
            permission = json.loads(sys.stdin.readline())
            send({
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "stopReason": "end_turn",
                    "permissionOutcome": permission["result"]["outcome"]
                }
            })
    """
  end
end
