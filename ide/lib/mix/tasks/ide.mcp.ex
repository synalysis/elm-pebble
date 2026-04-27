defmodule Mix.Tasks.Ide.Mcp do
  use Mix.Task

  @shortdoc "Runs the IDE MCP stdio server"
  @moduledoc """
  Starts a capability-scoped MCP server over stdio.

      mix ide.mcp --capabilities read,edit,build
  """

  alias Ide.Mcp.Protocol
  alias Ide.Mcp.Server
  alias Ide.Settings

  @impl Mix.Task
  @spec run(term()) :: term()
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [capabilities: :string]
      )

    capabilities =
      opts
      |> Keyword.get(:capabilities, settings_capabilities())
      |> Protocol.normalize_capabilities()

    Server.run(capabilities: capabilities)
  end

  defp settings_capabilities do
    Settings.current().mcp_http_capabilities
  rescue
    _ -> [:read]
  end
end
