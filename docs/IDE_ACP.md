# IDE ACP Client

The IDE can act as an Agent Client Protocol (ACP) client for local coding
agents. ACP is used for the user/session side of the integration, while the
existing IDE MCP server remains the tool surface that agents can connect to.

## Architecture

- `Ide.Acp.Client` launches an ACP agent subprocess and speaks JSON-RPC over
  newline-delimited stdio.
- `Ide.Acp.AgentSupervisor` supervises per-agent client processes.
- `Ide.Acp` provides public entry points for starting agents and creating IDE
  sessions.
- `Ide.Acp.McpServers` builds the IDE MCP server declaration passed in
  `session/new`.

This keeps ACP and MCP roles separate:

- ACP: IDE ↔ agent session lifecycle, prompts, streaming updates, permission
  requests.
- MCP: agent ↔ IDE tools such as project, file, compiler, package, and debugger
  operations.

## Minimal Flow

```elixir
{:ok, client} =
  Ide.Acp.start_agent(
    command: "/path/to/acp-agent",
    args: ["--stdio"],
    owner: self()
  )

{:ok, _initialize} = Ide.Acp.Client.initialize(client)

{:ok, %{"sessionId" => session_id}} =
  Ide.Acp.Client.new_ide_session(client, "/path/to/elm-pebble",
    ide_mcp: [capabilities: [:read, :edit, :build]]
  )

{:ok, %{"stopReason" => "end_turn"}} =
  Ide.Acp.Client.prompt_text(client, session_id, "Review the current project")
```

Agent `session/update` notifications are sent to the configured owner process:

```elixir
{:acp_notification, client, "session/update", params}
```

If an agent asks for `session/request_permission`, the initial implementation
answers conservatively by selecting a `reject_once` option when available, or
`cancelled` otherwise. UI-driven permission handling can layer on top of this
backend client.

## Passing IDE Tools To Agents

`Ide.Acp.Client.new_ide_session/3` attaches the IDE MCP server automatically.
The generated ACP MCP server entry uses stdio:

```json
{
  "name": "elm-pebble-ide",
  "command": "/usr/bin/bash",
  "args": [
    "-lc",
    "cd '/path/to/elm-pebble/ide' && exec mix ide.mcp --capabilities 'read,edit,build'"
  ],
  "env": []
}
```

Use `Ide.Acp.Client.new_session/3` instead when creating a session without IDE
MCP tools.

## Running As A Local ACP Agent

Zed and other ACP clients expect to launch an **agent** subprocess. The IDE also
ships a deterministic ACP agent bridge for local development:

```bash
cd ide
mix ide.acp_agent --capabilities read,edit,build
```

This command speaks newline-delimited ACP JSON-RPC over stdio. It is not an LLM;
it exposes IDE tool access through explicit commands:

```text
/tools
/tool projects.list {}
/tool compiler.check {"slug":"my-project"}
```

When `--capabilities` is omitted, the command reads its default ACP access
rights from **Settings → MCP / ACP access**. If the local ACP agent bridge is
disabled there, `mix ide.acp_agent` refuses to start.

Example Zed custom agent configuration:

```json
{
  "agent_servers": {
    "Elm Pebble IDE": {
      "type": "custom",
      "command": "bash",
      "args": [
        "-lc",
        "cd /path/to/elm-pebble/ide && exec mix ide.acp_agent --capabilities read,edit,build"
      ],
      "env": {}
    }
  }
}
```
