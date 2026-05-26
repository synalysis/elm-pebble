defmodule Ide.Debugger.TraceExchange.Export do
  @moduledoc false

  alias Ide.Debugger.SimulatorSettings
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TraceExchange.FingerprintCompare
  alias Ide.Debugger.TraceExchange.Wire
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | map()

  @type export_opts :: [
          disabled_subscriptions: [Types.disabled_subscription()],
          compare_cursor_seq: integer() | nil,
          baseline_cursor_seq: integer() | nil
        ]

  @spec payload(String.t(), runtime_state(), export_opts()) :: Types.import_trace_body()
  def payload(project_slug, state, opts) when is_binary(project_slug) and is_map(state) and is_list(opts) do
    events =
      state.events
      |> Enum.sort_by(& &1.seq)
      |> Wire.normalize_events_with_snapshot_refs()

    runtime_fingerprint_compare =
      FingerprintCompare.build(
        state.events,
        Keyword.get(opts, :compare_cursor_seq),
        Keyword.get(opts, :baseline_cursor_seq)
      )

    %{
      "companion" => Wire.normalize_term(Surface.to_map(Surface.from_state(state, :companion))),
      "debugger_seq" => Map.get(state, :debugger_seq, 0),
      "debugger_timeline" => Wire.normalize_term(Map.get(state, :debugger_timeline, [])),
      "disabled_subscriptions" => Wire.normalize_term(Keyword.fetch!(opts, :disabled_subscriptions)),
      "events" => events,
      "export_version" => 1,
      "phone" => Wire.normalize_term(Surface.to_map(Surface.from_state(state, :phone))),
      "project_slug" => project_slug,
      "revision" => Map.get(state, :revision),
      "running" => Map.get(state, :running, false),
      "watch_profile_id" => Map.get(state, :watch_profile_id),
      "launch_context" => Wire.normalize_term(Map.get(state, :launch_context, %{})),
      "simulator_settings" => Wire.normalize_term(SimulatorSettings.from_state(state)),
      "runtime_fingerprint_compare" => Wire.normalize_term(runtime_fingerprint_compare),
      "seq" => Map.get(state, :seq, 0),
      "watch" => Wire.normalize_term(Surface.to_map(Surface.from_state(state, :watch)))
    }
  end
end
