defmodule Ide.Debugger.Types.RuntimeEventAppend do
  @moduledoc """
  Resolves internal event kinds to wire `type` strings for `RuntimeState.events`.
  """

  alias Ide.Debugger.Types.{RuntimeEventLog, RuntimeEventPayload}

  @wire_types %{
    elmc_check: "debugger.elmc_check",
    elmc_compile: "debugger.elmc_compile",
    elmc_manifest: "debugger.elmc_manifest"
  }

  @spec wire_type(RuntimeEventPayload.event_kind() | :elmc_check | :elmc_compile | :elmc_manifest) ::
          String.t()
  def wire_type(kind) when is_atom(kind) do
    case Map.get(@wire_types, kind) do
      type when is_binary(type) ->
        type

      nil ->
        case RuntimeEventLog.event_type(kind) do
          type when is_binary(type) -> type
          _ -> raise ArgumentError, "unknown runtime event kind: #{inspect(kind)}"
        end
    end
  end

  @spec known_wire_type?(String.t()) :: boolean()
  def known_wire_type?(type) when is_binary(type) do
    RuntimeEventLog.wire_type?(type) or Map.has_key?(wire_types_by_string(), type)
  end

  @spec wire_types_by_string() :: map()
  defp wire_types_by_string do
    Map.merge(RuntimeEventLog.known_wire_types(), @wire_types)
  end
end
