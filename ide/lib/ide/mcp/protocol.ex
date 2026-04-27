defmodule Ide.Mcp.Protocol do
  @moduledoc """
  Protocol-level MCP JSON-RPC handling shared by stdio and HTTP transports.
  """

  alias Ide.Mcp.Audit
  alias Ide.Mcp.Tools

  @server_name "elm-pebble-ide-mcp"
  @server_version "0.1.0"
  @protocol_version "2024-11-05"

  @type capabilities :: [Tools.capability()]
  @type request_result :: {:ok, map() | nil} | {:error, integer(), String.t()}

  @doc """
  Handles an MCP JSON-RPC request body.

  Notifications return `nil`, because JSON-RPC notifications must not receive a
  response.
  """
  @spec response(map(), capabilities()) :: map() | nil
  def response(%{"id" => id} = request, capabilities) do
    case handle_request(request, capabilities) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, code, message} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
    end
  end

  def response(_notification, _capabilities), do: nil

  @doc """
  Handles a JSON-RPC batch and drops notification-only responses.
  """
  @spec batch_response([map()], capabilities()) :: [map()]
  def batch_response(messages, capabilities) when is_list(messages) do
    messages
    |> Enum.map(&response(&1, capabilities))
    |> Enum.reject(&is_nil/1)
  end

  @spec handle_request(map(), capabilities()) :: request_result()
  def handle_request(%{"method" => "initialize"}, capabilities) do
    {:ok,
     %{
       "protocolVersion" => @protocol_version,
       "serverInfo" => %{"name" => @server_name, "version" => @server_version},
       "capabilities" => %{"tools" => %{}},
       "meta" => %{"capabilities_scope" => Enum.map(capabilities, &Atom.to_string/1)}
     }}
  end

  def handle_request(%{"method" => "tools/list"}, capabilities) do
    {:ok,
     %{
       "tools" => Tools.tool_definitions(capabilities),
       "_meta" => %{"catalog_version" => Tools.catalog_version()}
     }}
  end

  def handle_request(
        %{"method" => "tools/call", "params" => %{"name" => name} = params},
        capabilities
      ) do
    args = Map.get(params, "arguments", %{})
    trace_id = trace_id()

    case Tools.call(name, args, capabilities) do
      {:ok, payload} ->
        audit(name, "ok", trace_id, params)

        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => Jason.encode!(payload)}],
           "isError" => false,
           "_meta" => %{"trace_id" => trace_id}
         }}

      {:error, reason} ->
        audit(name, "error", trace_id, params, reason)

        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => reason}],
           "isError" => true,
           "_meta" => %{"trace_id" => trace_id}
         }}
    end
  end

  def handle_request(%{"method" => _other}, _capabilities) do
    {:error, -32601, "method not found"}
  end

  def handle_request(_request, _capabilities) do
    {:error, -32600, "invalid request"}
  end

  @spec normalize_capabilities(term()) :: capabilities()
  def normalize_capabilities(capabilities) when is_binary(capabilities) do
    capabilities
    |> String.split(",", trim: true)
    |> normalize_capabilities()
  end

  def normalize_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.map(&normalize_capability/1)
    |> Enum.filter(&(&1 in [:read, :edit, :build]))
    |> case do
      [] -> [:read]
      list -> Enum.uniq(list)
    end
  end

  def normalize_capabilities(_capabilities), do: [:read]

  defp normalize_capability(:read), do: :read
  defp normalize_capability(:edit), do: :edit
  defp normalize_capability(:build), do: :build
  defp normalize_capability(capability) when is_atom(capability), do: nil

  defp normalize_capability(capability) do
    case capability |> to_string() |> String.trim() |> String.downcase() do
      "read" -> :read
      "edit" -> :edit
      "build" -> :build
      _other -> nil
    end
  end

  @spec audit(term(), term(), term(), term(), term()) :: term()
  defp audit(action, status, trace_id, params, error_message \\ nil) do
    entry = %{
      at: DateTime.utc_now() |> DateTime.to_iso8601(),
      trace_id: trace_id,
      action: action,
      status: status,
      arguments: params |> Map.get("arguments", %{}) |> then(&Tools.audit_arguments(action, &1))
    }

    entry =
      if is_binary(error_message) do
        Map.put(entry, :error, error_message)
      else
        entry
      end

    Audit.append(entry)
  end

  @spec trace_id() :: String.t()
  defp trace_id do
    "trace_" <> Integer.to_string(System.unique_integer([:positive]), 36)
  end
end
