defmodule Ide.Mcp.Protocol do
  @moduledoc """
  Protocol-level MCP JSON-RPC handling shared by stdio and HTTP transports.
  """

  alias Ide.Mcp.Audit
  alias Ide.Mcp.Tools
  alias Ide.Mcp.WireTypes

  @server_name "elm-pebble-ide-mcp"
  @server_version "0.1.0"
  @protocol_version "2024-11-05"

  @type capabilities :: [Tools.capability()]
  @type json_rpc_id :: integer() | String.t() | nil
  @type json_rpc_request :: %{
          required(String.t()) => WireTypes.json_value(),
          optional(String.t()) => WireTypes.json_value()
        }
  @type json_rpc_error :: %{
          required(String.t()) => integer() | String.t()
        }
  @type json_rpc_response :: %{
          required(String.t()) =>
            String.t() | json_rpc_id() | WireTypes.json_value() | json_rpc_error()
        }
  @type request_result :: {:ok, WireTypes.json_value()} | {:error, integer(), String.t()}

  @type json_safe_datetime :: Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t()

  @type json_safe_opaque :: pid() | reference() | function() | port() | tuple()

  @typedoc "Values accepted by MCP JSON encoding (tool payloads, datetimes, opaque terms)."
  @type json_safe_input ::
          WireTypes.json_value()
          | atom()
          | json_safe_datetime()
          | json_safe_opaque()
          | map()

  @doc """
  Handles an MCP JSON-RPC request body.

  Notifications return `nil`, because JSON-RPC notifications must not receive a
  response.
  """
  @spec response(json_rpc_request(), capabilities()) :: json_rpc_response() | nil
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
  @spec batch_response([json_rpc_request()], capabilities()) :: [json_rpc_response()]
  def batch_response(messages, capabilities) when is_list(messages) do
    messages
    |> Enum.map(&response(&1, capabilities))
    |> Enum.reject(&is_nil/1)
  end

  @spec handle_request(json_rpc_request(), capabilities()) :: request_result()
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
           "content" => [%{"type" => "text", "text" => Jason.encode!(json_safe(payload))}],
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

  @type capability_input :: String.t() | atom()

  @doc false
  @spec json_safe(json_safe_input()) :: WireTypes.json_value()
  def json_safe(value)
      when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
      do: value

  def json_safe(value) when is_atom(value), do: Atom.to_string(value)

  def json_safe(%Date{} = value), do: Date.to_iso8601(value)
  def json_safe(%Time{} = value), do: Time.to_iso8601(value)
  def json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def json_safe(value)
      when is_pid(value) or is_reference(value) or is_function(value) or is_port(value),
      do: inspect(value)

  def json_safe(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&json_safe/1)
  end

  def json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  def json_safe(%_{} = value), do: inspect(value)

  def json_safe(value) when is_map(value) do
    Map.new(value, fn {key, member} -> {json_safe_key(key), json_safe(member)} end)
  end

  def json_safe(value), do: inspect(value)

  @spec json_safe_key(String.t() | atom()) :: String.t()
  defp json_safe_key(key) when is_binary(key), do: key
  defp json_safe_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_safe_key(key), do: inspect(key)

  @spec normalize_capabilities(String.t() | [capability_input()]) :: capabilities()
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

  @spec audit(String.t(), String.t(), String.t(), json_rpc_request(), String.t() | nil) :: :ok
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
