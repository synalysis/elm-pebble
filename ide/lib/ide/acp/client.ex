defmodule Ide.Acp.Client do
  @moduledoc """
  JSON-RPC client for ACP agents over stdio.

  ACP's stdio transport is newline-delimited JSON, which is intentionally
  separate from the IDE MCP server's `Content-Length` framing.
  """

  use GenServer

  alias Ide.Acp.McpServers

  @protocol_version 1
  @default_timeout 30_000

  defstruct [
    :port,
    :owner,
    :command,
    args: [],
    cwd: nil,
    env: [],
    next_id: 0,
    pending: %{},
    default_timeout: @default_timeout,
    client_info: %{
      "name" => "elm-pebble-ide",
      "title" => "Elm Pebble IDE",
      "version" => "0.1.0"
    },
    client_capabilities: %{}
  ]

  @type request_result :: {:ok, map() | list() | nil} | {:error, term()}

  @doc """
  Starts an ACP client and launches the configured agent subprocess.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Initializes the ACP connection.
  """
  @spec initialize(GenServer.server(), keyword()) :: request_result()
  def initialize(client, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(client, {:initialize, opts, timeout}, timeout + 1_000)
  end

  @doc """
  Creates a raw ACP session.
  """
  @spec new_session(GenServer.server(), String.t(), keyword()) :: request_result()
  def new_session(client, cwd, opts \\ []) when is_binary(cwd) do
    params = %{
      "cwd" => Path.expand(cwd),
      "mcpServers" => Keyword.get(opts, :mcp_servers, [])
    }

    request(client, "session/new", params, Keyword.get(opts, :timeout, @default_timeout))
  end

  @doc """
  Creates an ACP session with the IDE's MCP server attached.
  """
  @spec new_ide_session(GenServer.server(), String.t(), keyword()) :: request_result()
  def new_ide_session(client, cwd, opts \\ []) when is_binary(cwd) do
    mcp_servers =
      opts
      |> Keyword.get(:mcp_servers, [])
      |> List.wrap()
      |> Kernel.++([McpServers.ide_stdio(Keyword.get(opts, :ide_mcp, []))])

    new_session(client, cwd, Keyword.put(opts, :mcp_servers, mcp_servers))
  end

  @doc """
  Loads a persisted ACP session when the agent advertises `loadSession`.
  """
  @spec load_session(GenServer.server(), String.t(), String.t(), keyword()) :: request_result()
  def load_session(client, session_id, cwd, opts \\ []) do
    params = %{
      "sessionId" => session_id,
      "cwd" => Path.expand(cwd),
      "mcpServers" => Keyword.get(opts, :mcp_servers, [])
    }

    request(client, "session/load", params, Keyword.get(opts, :timeout, @default_timeout))
  end

  @doc """
  Resumes an active ACP session without replay when the agent supports it.
  """
  @spec resume_session(GenServer.server(), String.t(), String.t(), keyword()) :: request_result()
  def resume_session(client, session_id, cwd, opts \\ []) do
    params = %{
      "sessionId" => session_id,
      "cwd" => Path.expand(cwd),
      "mcpServers" => Keyword.get(opts, :mcp_servers, [])
    }

    request(client, "session/resume", params, Keyword.get(opts, :timeout, @default_timeout))
  end

  @doc """
  Sends content blocks to an ACP session.
  """
  @spec prompt(GenServer.server(), String.t(), [map()], keyword()) :: request_result()
  def prompt(client, session_id, content_blocks, opts \\ [])
      when is_binary(session_id) and is_list(content_blocks) do
    params = %{"sessionId" => session_id, "prompt" => content_blocks}
    request(client, "session/prompt", params, Keyword.get(opts, :timeout, @default_timeout))
  end

  @doc """
  Convenience wrapper for a plain text prompt.
  """
  @spec prompt_text(GenServer.server(), String.t(), String.t(), keyword()) :: request_result()
  def prompt_text(client, session_id, text, opts \\ []) when is_binary(text) do
    prompt(client, session_id, [%{"type" => "text", "text" => text}], opts)
  end

  @doc """
  Sends an ACP cancellation notification.
  """
  @spec cancel(GenServer.server(), String.t()) :: :ok
  def cancel(client, session_id) do
    notify(client, "session/cancel", %{"sessionId" => session_id})
  end

  @doc """
  Closes an active ACP session when the agent supports `session/close`.
  """
  @spec close_session(GenServer.server(), String.t(), keyword()) :: request_result()
  def close_session(client, session_id, opts \\ []) do
    request(
      client,
      "session/close",
      %{"sessionId" => session_id},
      Keyword.get(opts, :timeout, @default_timeout)
    )
  end

  @doc """
  Sends a raw JSON-RPC request to the agent.
  """
  @spec request(GenServer.server(), String.t(), map() | list() | nil, timeout()) ::
          request_result()
  def request(client, method, params, timeout \\ @default_timeout) when is_binary(method) do
    GenServer.call(client, {:request, method, params, timeout}, timeout + 1_000)
  end

  @doc """
  Sends a raw JSON-RPC notification to the agent.
  """
  @spec notify(GenServer.server(), String.t(), map() | list() | nil) :: :ok
  def notify(client, method, params) when is_binary(method) do
    GenServer.cast(client, {:notify, method, params})
  end

  @impl true
  def init(opts) do
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, [])

    port_opts =
      [
        :binary,
        :exit_status,
        {:line, Keyword.get(opts, :max_line_length, 1_000_000)},
        {:args, args}
      ]
      |> put_port_option(:cd, cwd)
      |> put_port_option(:env, port_env(env))

    port = Port.open({:spawn_executable, command}, port_opts)

    {:ok,
     %__MODULE__{
       port: port,
       owner: Keyword.get(opts, :owner, self()),
       command: command,
       args: args,
       cwd: cwd,
       env: env,
       default_timeout: Keyword.get(opts, :timeout, @default_timeout),
       client_info: Keyword.get(opts, :client_info, %__MODULE__{}.client_info),
       client_capabilities: Keyword.get(opts, :client_capabilities, %{})
     }}
  end

  @impl true
  def handle_call({:initialize, opts, timeout}, from, state) do
    params = %{
      "protocolVersion" => @protocol_version,
      "clientCapabilities" => Keyword.get(opts, :client_capabilities, state.client_capabilities),
      "clientInfo" => Keyword.get(opts, :client_info, state.client_info)
    }

    send_request("initialize", params, timeout, from, state)
  end

  def handle_call({:request, method, params, timeout}, from, state) do
    send_request(method, params, timeout, from, state)
  end

  @impl true
  def handle_cast({:notify, method, params}, state) do
    _ignored =
      write_message(state.port, %{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params || %{}
      })

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    handle_line(line, state)
  end

  def handle_info({port, {:data, {:noeol, line}}}, %{port: port} = state) do
    handle_line(line, state)
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Enum.each(state.pending, fn {_id, pending} ->
      Process.cancel_timer(pending.timer)
      GenServer.reply(pending.from, {:error, {:agent_exit, status}})
    end)

    send(state.owner, {:acp_agent_exit, self(), status})
    {:stop, {:agent_exit, status}, %{state | pending: %{}}}
  end

  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, pending} ->
        {:noreply, %{state | pending: pending}}

      {pending_request, pending} ->
        GenServer.reply(pending_request.from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, reason} ->
        send(state.owner, {:acp_protocol_error, self(), {:invalid_json, reason, line}})
        {:noreply, state}
    end
  end

  defp handle_message(%{"id" => id, "method" => method, "params" => params}, state) do
    response =
      case handle_agent_request(method, params) do
        {:ok, result} ->
          %{"jsonrpc" => "2.0", "id" => id, "result" => result}

        {:error, code, message} ->
          %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
      end

    _ignored = write_message(state.port, response)
    {:noreply, state}
  end

  defp handle_message(%{"id" => id, "method" => method}, state) do
    handle_message(%{"id" => id, "method" => method, "params" => %{}}, state)
  end

  defp handle_message(%{"id" => id} = message, state) do
    case Map.pop(state.pending, id) do
      {nil, pending} ->
        send(state.owner, {:acp_unmatched_response, self(), message})
        {:noreply, %{state | pending: pending}}

      {pending_request, pending} ->
        Process.cancel_timer(pending_request.timer)
        GenServer.reply(pending_request.from, response_result(message))
        {:noreply, %{state | pending: pending}}
    end
  end

  defp handle_message(%{"method" => method, "params" => params}, state) do
    send(state.owner, {:acp_notification, self(), method, params})
    {:noreply, state}
  end

  defp handle_message(message, state) do
    send(state.owner, {:acp_protocol_error, self(), {:unknown_message, message}})
    {:noreply, state}
  end

  defp response_result(%{"result" => result}), do: {:ok, result}
  defp response_result(%{"error" => error}), do: {:error, error}
  defp response_result(_message), do: {:error, :invalid_response}

  defp handle_agent_request("session/request_permission", %{"options" => options})
       when is_list(options) do
    reject_once =
      Enum.find(options, fn option ->
        Map.get(option, "kind") == "reject_once" or Map.get(option, "name") in ["Reject", "Deny"]
      end)

    case reject_once do
      %{"optionId" => option_id} ->
        {:ok, %{"outcome" => %{"outcome" => "selected", "optionId" => option_id}}}

      _other ->
        {:ok, %{"outcome" => %{"outcome" => "cancelled"}}}
    end
  end

  defp handle_agent_request(method, _params) do
    {:error, -32601, "ACP client method not implemented: #{method}"}
  end

  defp send_request(method, params, timeout, from, state) do
    id = state.next_id
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params || %{}}

    with :ok <- write_message(state.port, message) do
      timer = Process.send_after(self(), {:request_timeout, id}, timeout)
      pending = Map.put(state.pending, id, %{from: from, timer: timer, method: method})

      {:noreply, %{state | next_id: id + 1, pending: pending}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp write_message(port, message) do
    encoded = Jason.encode!(message)
    true = Port.command(port, encoded <> "\n")
    :ok
  rescue
    error -> {:error, error}
  end

  defp put_port_option(options, _key, nil), do: options
  defp put_port_option(options, _key, []), do: options
  defp put_port_option(options, key, value), do: options ++ [{key, value}]

  defp port_env(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp port_env(env) when is_list(env) do
    Enum.map(env, fn
      {key, value} -> {to_string(key), to_string(value)}
      %{"name" => key, "value" => value} -> {to_string(key), to_string(value)}
      %{name: key, value: value} -> {to_string(key), to_string(value)}
    end)
  end

  defp port_env(_env), do: []
end
