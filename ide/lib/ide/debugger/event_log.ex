defmodule Ide.Debugger.EventLog do
  @moduledoc false

  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.RuntimeEvent
  alias Ide.Debugger.Types.RuntimeEventPayload

  @default_history_limit 500

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @spec append(
          Types.runtime_state(),
          String.t(),
          RuntimeEventPayload.t(),
          keyword()
        ) :: Types.runtime_state()
  def append(state, type, payload, opts \\ [])
      when is_map(state) and is_binary(type) and is_map(payload) do
    limit = Keyword.get(opts, :limit, @default_history_limit)
    seq = state.seq + 1

    event =
      RuntimeEvent.build(seq, type, payload, %{
        watch: Map.get(state, :watch, %{}),
        companion: Map.get(state, :companion, %{}),
        phone: Map.get(state, :phone, %{})
      })

    %{
      state
      | seq: seq,
        events: [event | state.events] |> Enum.take(limit)
    }
  end

  @spec append_debugger_event(
          Types.runtime_state(),
          String.t(),
          Types.surface_target(),
          String.t() | Types.wire_input(),
          String.t() | nil,
          keyword()
        ) :: Types.runtime_state()
  def append_debugger_event(state, type, target, message, message_source, opts \\ [])
      when is_map(state) and is_binary(type) and target in [:watch, :companion, :phone] do
    limit = Keyword.get(opts, :limit, @default_history_limit)
    source_root = Keyword.get(opts, :source_root_for_target, &SurfaceTargets.source_root/1)

    debugger_seq = Map.get(state, :debugger_seq, 0) + 1
    message_value = Keyword.get(opts, :message_value)

    row = %{
      seq: debugger_seq,
      raw_seq: Map.get(state, :seq, 0),
      type: type,
      target: source_root.(target),
      message:
        if(is_binary(message),
          do: TimelineMessage.format(message, message_value),
          else: TimelineMessage.format(to_string(message || ""), message_value)
        ),
      message_source: if(is_binary(message_source), do: message_source, else: nil),
      watch: Map.get(state, :watch, %{}),
      companion: Map.get(state, :companion, %{}),
      phone: Map.get(state, :phone, %{})
    }

    state
    |> Map.put(:debugger_seq, debugger_seq)
    |> Map.put(
      :debugger_timeline,
      [row | Map.get(state, :debugger_timeline, [])] |> Enum.take(limit)
    )
  end

  @spec trim(Types.runtime_state(), pos_integer() | Types.wire_input()) :: Types.runtime_state()
  def trim(state, limit) when is_map(state) and is_integer(limit) and limit > 0 do
    %{state | events: Enum.take(state.events, limit)}
  end

  def trim(state, _limit), do: state
end
