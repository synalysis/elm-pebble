defmodule Ide.Acp.AgentProtocolTest do
  use Ide.DataCase, async: false

  alias Ide.Acp.AgentProtocol

  test "initializes as an ACP agent" do
    state = AgentProtocol.new(capabilities: [:read, :build])

    {_state, [response]} =
      AgentProtocol.handle_message(
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"},
        state
      )

    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == 1
    assert response["result"]["agentInfo"]["name"] == "elm-pebble-ide-agent"
  end

  test "creates a session and lists available IDE tools" do
    state = AgentProtocol.new(capabilities: [:read])

    {state, [%{"result" => %{"sessionId" => session_id}}]} =
      AgentProtocol.handle_message(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "session/new",
          "params" => %{"cwd" => "/tmp"}
        },
        state
      )

    {_state, [update, response]} =
      AgentProtocol.handle_message(
        %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "session/prompt",
          "params" => %{
            "sessionId" => session_id,
            "prompt" => [%{"type" => "text", "text" => "/tools"}]
          }
        },
        state
      )

    assert update["method"] == "session/update"
    assert update["params"]["update"]["content"]["text"] =~ "projects.list"
    assert response["result"]["stopReason"] == "end_turn"
  end

  test "runs explicit IDE tool invocations" do
    state = AgentProtocol.new(capabilities: [:read])

    {state, [%{"result" => %{"sessionId" => session_id}}]} =
      AgentProtocol.handle_message(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "session/new",
          "params" => %{"cwd" => "/tmp"}
        },
        state
      )

    {_state, [update, response]} =
      AgentProtocol.handle_message(
        %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "session/prompt",
          "params" => %{
            "sessionId" => session_id,
            "prompt" => [%{"type" => "text", "text" => "/tool projects.list {}"}]
          }
        },
        state
      )

    assert update["params"]["update"]["content"]["text"] =~ "projects"
    assert response["result"]["stopReason"] == "end_turn"
  end
end
