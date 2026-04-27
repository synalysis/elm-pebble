defmodule Ide.Acp.AgentProtocol do
  @moduledoc """
  Minimal ACP agent implementation for exposing IDE capabilities to ACP clients.

  This is intentionally deterministic: it does not wrap an LLM. It lets ACP
  clients such as Zed launch the IDE as an external agent, inspect available
  IDE tools, and invoke those tools explicitly.
  """

  alias Ide.Mcp.Protocol, as: McpProtocol
  alias Ide.Mcp.Tools

  @protocol_version 1

  defstruct capabilities: [:read],
            sessions: %{}

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      capabilities:
        opts |> Keyword.get(:capabilities, [:read]) |> McpProtocol.normalize_capabilities()
    }
  end

  @spec handle_message(map(), t()) :: {t(), [map()]}
  def handle_message(%{"id" => id, "method" => method, "params" => params}, state) do
    handle_request(id, method, params || %{}, state)
  end

  def handle_message(%{"id" => id, "method" => method}, state) do
    handle_request(id, method, %{}, state)
  end

  def handle_message(
        %{"method" => "session/cancel", "params" => %{"sessionId" => session_id}},
        state
      ) do
    notification = session_update(session_id, text_update("Prompt cancelled."))
    {state, [notification]}
  end

  def handle_message(_message, state), do: {state, []}

  defp handle_request(id, "initialize", _params, state) do
    result = %{
      "protocolVersion" => @protocol_version,
      "agentCapabilities" => %{
        "promptCapabilities" => %{"embeddedContext" => true},
        "sessionCapabilities" => %{"close" => %{}}
      },
      "agentInfo" => %{
        "name" => "elm-pebble-ide-agent",
        "title" => "Elm Pebble IDE Agent",
        "version" => "0.1.0"
      },
      "authMethods" => []
    }

    {state, [success(id, result)]}
  end

  defp handle_request(id, "session/new", params, state) do
    session_id = "ide-acp-" <> Integer.to_string(System.unique_integer([:positive]), 36)

    session = %{
      cwd: Map.get(params, "cwd"),
      mcp_servers: Map.get(params, "mcpServers", [])
    }

    state = put_in(state.sessions[session_id], session)
    {state, [success(id, %{"sessionId" => session_id})]}
  end

  defp handle_request(
         id,
         "session/prompt",
         %{"sessionId" => session_id, "prompt" => prompt},
         state
       ) do
    text = prompt_text(prompt)
    {updates, stop_reason} = prompt_updates(session_id, text, state)

    {state, updates ++ [success(id, %{"stopReason" => stop_reason})]}
  end

  defp handle_request(id, "session/close", %{"sessionId" => session_id}, state) do
    {state, [success(id, %{})]}
    |> then(fn {_state, messages} ->
      {%{state | sessions: Map.delete(state.sessions, session_id)}, messages}
    end)
  end

  defp handle_request(id, method, _params, state) do
    {state, [error(id, -32601, "ACP agent method not implemented: #{method}")]}
  end

  defp prompt_updates(session_id, text, state) do
    cond do
      String.trim(text) in ["", "/help", "help"] ->
        {[session_update(session_id, text_update(help_text()))], "end_turn"}

      String.trim(text) == "/tools" ->
        tool_names =
          state.capabilities
          |> Tools.tool_definitions()
          |> Enum.map(& &1.name)
          |> Enum.sort()
          |> Enum.join("\n")

        {[session_update(session_id, text_update("Available IDE MCP tools:\n\n" <> tool_names))],
         "end_turn"}

      String.starts_with?(String.trim(text), "/tool ") ->
        {[session_update(session_id, text_update(run_tool(text, state.capabilities)))],
         "end_turn"}

      true ->
        {[session_update(session_id, text_update(help_text()))], "end_turn"}
    end
  end

  defp run_tool(text, capabilities) do
    case parse_tool_invocation(text) do
      {:ok, name, args} ->
        request = %{
          "id" => "prompt-tool-call",
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => args}
        }

        request
        |> McpProtocol.response(capabilities)
        |> format_mcp_response()

      {:error, reason} ->
        reason
    end
  end

  defp parse_tool_invocation(text) do
    case text |> String.trim() |> String.split(~r/\s+/, parts: 3) do
      ["/tool", name] ->
        {:ok, name, %{}}

      ["/tool", name, json] ->
        case Jason.decode(json) do
          {:ok, args} when is_map(args) -> {:ok, name, args}
          {:ok, _other} -> {:error, "Tool arguments must be a JSON object."}
          {:error, error} -> {:error, "Invalid JSON arguments: #{Exception.message(error)}"}
        end

      _other ->
        {:error, "Use `/tool TOOL_NAME {\"arg\":\"value\"}`."}
    end
  end

  defp format_mcp_response(%{"result" => %{"content" => [%{"text" => text}], "isError" => false}}),
    do: text

  defp format_mcp_response(%{"result" => %{"content" => [%{"text" => text}], "isError" => true}}),
    do: "Tool error: " <> text

  defp format_mcp_response(%{"error" => %{"message" => message}}), do: "MCP error: " <> message
  defp format_mcp_response(response), do: Jason.encode!(response)

  defp prompt_text(prompt) when is_list(prompt) do
    prompt
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} when is_binary(text) -> [text]
      _other -> []
    end)
    |> Enum.join("\n")
  end

  defp prompt_text(_prompt), do: ""

  defp help_text do
    """
    Elm Pebble IDE ACP agent is connected.

    This agent is a deterministic IDE bridge, not an LLM. Use:

    /tools
    /tool TOOL_NAME {"arg":"value"}

    Example:

    /tool projects.list {}
    """
    |> String.trim()
  end

  defp session_update(session_id, update) do
    %{
      "jsonrpc" => "2.0",
      "method" => "session/update",
      "params" => %{"sessionId" => session_id, "update" => update}
    }
  end

  defp text_update(text) do
    %{
      "sessionUpdate" => "agent_message_chunk",
      "content" => %{"type" => "text", "text" => text}
    }
  end

  defp success(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
