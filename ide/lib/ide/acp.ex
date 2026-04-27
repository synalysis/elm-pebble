defmodule Ide.Acp do
  @moduledoc """
  Public entry points for talking to ACP-compatible coding agents.
  """

  alias Ide.Acp.{AgentSupervisor, Client, McpServers}

  @doc """
  Starts a supervised ACP agent client.
  """
  @spec start_agent(keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(opts) do
    DynamicSupervisor.start_child(AgentSupervisor, {Client, opts})
  end

  @doc """
  Starts an agent, initializes ACP, and creates a session with IDE MCP tools.
  """
  @spec start_ide_session(keyword(), String.t(), keyword()) ::
          {:ok, pid(), map()} | {:error, term()}
  def start_ide_session(agent_opts, cwd, session_opts \\ []) do
    with {:ok, client} <- start_agent(agent_opts),
         {:ok, _initialize} <-
           Client.initialize(client, Keyword.get(session_opts, :initialize, [])),
         {:ok, session} <-
           Client.new_ide_session(client, cwd, Keyword.get(session_opts, :session, [])) do
      {:ok, client, session}
    end
  end

  @doc """
  Returns the IDE MCP server declaration suitable for ACP `session/new`.
  """
  @spec ide_mcp_server(keyword()) :: map()
  def ide_mcp_server(opts \\ []) do
    McpServers.ide_stdio(opts)
  end
end
