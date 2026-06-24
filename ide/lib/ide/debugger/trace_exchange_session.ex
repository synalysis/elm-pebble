defmodule Ide.Debugger.TraceExchangeSession do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.AutoTickWorkers
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.TraceExchange
  alias Ide.Debugger.Types

  @type snapshot_fn :: (String.t(), keyword() -> {:ok, Types.runtime_state()})

  @type human_slug_fn :: (String.t() -> String.t())

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type put_state_fn ::
          (String.t(), Types.runtime_state(), keyword() -> Types.runtime_state())

  @type export_host :: %{
          required(:snapshot) => snapshot_fn(),
          required(:human_slug_from_session_key) => human_slug_fn(),
          required(:history_limit) => pos_integer()
        }

  @type import_host :: %{
          required(:human_slug_from_session_key) => human_slug_fn(),
          required(:ensure_phone_state) => ensure_phone_fn(),
          required(:put_state) => put_state_fn()
        }

  @spec export(String.t(), Types.export_trace_opts(), export_host()) ::
          {:ok, Types.export_trace_result()} | {:error, term()}
  def export(project_slug, opts, host)
      when is_binary(project_slug) and is_list(opts) and is_map(host) do
    limit = Keyword.get(opts, :event_limit, host.history_limit)
    compare_cursor_seq = Keyword.get(opts, :compare_cursor_seq)
    baseline_cursor_seq = Keyword.get(opts, :baseline_cursor_seq)

    limit =
      if is_integer(limit) and limit > 0,
        do: min(limit, host.history_limit),
        else: host.history_limit

    with {:ok, state} <- host.snapshot.(project_slug, event_limit: limit) do
      human_slug = Map.get(state, :project_slug, host.human_slug_from_session_key.(project_slug))

      body =
        TraceExchange.export_payload(human_slug, state,
          compare_cursor_seq: compare_cursor_seq,
          baseline_cursor_seq: baseline_cursor_seq,
          disabled_subscriptions: SubscriptionAutoFireState.disabled_subscriptions(state)
        )

      json = Jason.encode!(body)
      sha = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
      {:ok, %{json: json, sha256: sha, byte_size: byte_size(json)}}
    end
  end

  @spec import(String.t(), Types.import_trace_input(), keyword(), import_host()) ::
          {:ok, Types.runtime_state()}
          | {:error, Types.protocol_error() | atom() | String.t() | Types.wire_map()}
  def import(session_key, input, opts, host)
      when is_binary(session_key) and is_map(host) do
    human_slug = host.human_slug_from_session_key.(session_key)

    with {:ok, body} <- TraceExchange.decode_import_body(input),
         :ok <- TraceExchange.validate_import_body(body),
         :ok <- TraceExchange.maybe_match_import_slug(body, human_slug, opts) do
      state =
        TraceExchange.parse_import_state(body,
          parse_watch_profile_id: &RuntimeSurfaces.parse_watch_profile_id/1,
          parse_cursor_seq: &Attrs.parse_optional_cursor_seq/1
        )
        |> host.ensure_phone_state.()
        |> SimulatorSurfaceSettings.apply_to_state()
        |> Map.put(:scope_key, session_key)
        |> Map.put(:project_slug, human_slug)

      {:ok, host.put_state.(session_key, state, on_previous: &AutoTickWorkers.stop_worker/1)}
    end
  end
end
