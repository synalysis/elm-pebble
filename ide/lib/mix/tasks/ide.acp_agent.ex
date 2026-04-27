defmodule Mix.Tasks.Ide.AcpAgent do
  use Mix.Task

  @shortdoc "Runs the IDE ACP stdio agent"
  @moduledoc """
  Starts the IDE as a deterministic ACP agent over stdio.

      mix ide.acp_agent --capabilities read,edit,build
  """

  alias Ide.Acp.AgentServer
  alias Ide.Mcp.Protocol
  alias Ide.Settings

  @impl Mix.Task
  @spec run(term()) :: term()
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [capabilities: :string]
      )

    unless settings_enabled?() do
      Mix.raise("ACP agent bridge is disabled in IDE settings")
    end

    capabilities =
      opts
      |> Keyword.get(:capabilities, settings_capabilities())
      |> Protocol.normalize_capabilities()

    AgentServer.run(capabilities: capabilities)
  end

  defp settings_capabilities do
    Settings.current().acp_agent_capabilities
  rescue
    _ -> [:read]
  end

  defp settings_enabled? do
    Settings.current().acp_agent_enabled
  rescue
    _ -> true
  end
end
