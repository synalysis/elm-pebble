defmodule Ide.Debugger.RuntimeStatusFacades do
  @moduledoc false

  alias Ide.Debugger.DebuggerContractSnapshot
  alias Ide.Debugger.RuntimeStatusEvents
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t() ->
             Types.runtime_state())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          required(:append_debugger_event) => append_debugger_event_fn(),
          required(:source_root_for_target) => source_root_fn()
        }

  @contract_event_type "debugger.contract"

  @spec maybe_append_contract(host(), Types.runtime_state(), Types.debugger_contract() | nil) ::
          Types.runtime_state()
  def maybe_append_contract(_host, state, nil), do: state

  def maybe_append_contract(host, state, payload)
      when is_map(host) and is_map(state) and is_map(payload) do
    host.append_event.(state, @contract_event_type, payload)
  end

  def maybe_append_contract(_host, state, _payload), do: state

  @spec maybe_append_runtime_exec(host(), Types.runtime_state(), String.t()) ::
          Types.runtime_state()
  def maybe_append_runtime_exec(host, state, source_root)
      when is_map(host) and is_map(state) and is_binary(source_root) do
    RuntimeStatusEvents.append_runtime_exec_for_source_root(
      state,
      source_root,
      host.append_event,
      host.source_root_for_target,
      &DebuggerContractSnapshot.target_key/1
    )
  end

  @spec append_runtime_exec_for_target(
          host(),
          Types.runtime_state(),
          Types.surface_target(),
          map()
        ) :: Types.runtime_state()
  def append_runtime_exec_for_target(host, state, target, extra)
      when is_map(host) and is_map(state) and target in [:watch, :companion, :phone] and
             is_map(extra) do
    RuntimeStatusEvents.append_runtime_exec(
      state,
      target,
      extra,
      host.append_event,
      host.source_root_for_target
    )
  end

  @spec maybe_append_simple_status(host(), Types.runtime_state(), Types.surface_target()) ::
          Types.runtime_state()
  def maybe_append_simple_status(host, state, target)
      when is_map(host) and is_map(state) and target in [:watch, :companion, :phone] do
    RuntimeStatusEvents.maybe_append_simple_status(state, target, host.append_debugger_event)
  end

  def maybe_append_simple_status(_host, state, _target), do: state

  @spec maybe_append_after_execution(
          host(),
          Types.runtime_state(),
          Types.surface_target(),
          map(),
          Types.elm_introspect() | map()
        ) :: Types.runtime_state()
  def maybe_append_after_execution(host, state, target, execution, introspect)
      when is_map(host) and is_map(state) and target in [:watch, :companion, :phone] and
             is_map(execution) do
    RuntimeStatusEvents.maybe_append_after_execution(
      state,
      target,
      execution,
      introspect,
      host.append_event,
      host.append_debugger_event,
      host.source_root_for_target
    )
  end

  def maybe_append_after_execution(_host, state, _target, _execution, _introspect), do: state
end
