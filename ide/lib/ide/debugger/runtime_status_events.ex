defmodule Ide.Debugger.RuntimeStatusEvents do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type append_debugger_event_fn ::
          (Types.runtime_state(),
           String.t(),
           Types.surface_target(),
           String.t(),
           String.t(),
           Types.timeline_step_message_value() ->
             Types.runtime_state())

  @spec append_runtime_exec(
          Types.runtime_state(),
          Types.surface_target(),
          Types.RuntimeExecEventPayload.extra(),
          append_event_fn(),
          (Types.surface_target() -> String.t())
        ) :: Types.runtime_state()
  def append_runtime_exec(state, target, extra, append_event, source_root_for_target)
      when target in [:watch, :companion, :phone] and is_map(extra) and
             is_function(append_event, 3) and
             is_function(source_root_for_target, 1) do
    runtime = get_in(state, [target, :model, "runtime_execution"])

    if is_map(runtime) and map_size(runtime) > 0 do
      payload =
        Types.RuntimeExecEventPayload.from_runtime(
          runtime,
          source_root_for_target.(target),
          extra
        )

      append_event.(state, "debugger.runtime_exec", payload)
    else
      state
    end
  end

  def append_runtime_exec(state, _target, _extra, _append_event, _source_root_for_target),
    do: state

  @spec append_runtime_exec_for_source_root(
          Types.runtime_state(),
          String.t(),
          append_event_fn(),
          (Types.surface_target() -> String.t()),
          (String.t() -> Types.surface_target())
        ) :: Types.runtime_state()
  def append_runtime_exec_for_source_root(
        state,
        source_root,
        append_event,
        source_root_for_target,
        target_key
      )
      when is_binary(source_root) do
    append_runtime_exec(
      state,
      target_key.(source_root),
      %{},
      append_event,
      source_root_for_target
    )
  end

  @spec maybe_append_simple_status(
          Types.runtime_state(),
          Types.surface_target(),
          append_debugger_event_fn()
        ) :: Types.runtime_state()
  def maybe_append_simple_status(state, target, append_debugger_event)
      when target in [:watch, :companion, :phone] and
             (is_function(append_debugger_event, 5) or is_function(append_debugger_event, 6)) do
    runtime = get_in(state, [target, :model, "runtime_execution"])

    case status_message(runtime) do
      nil -> state
      message -> append_debugger_event.(state, "runtime", target, message, "runtime_status", nil)
    end
  end

  def maybe_append_simple_status(state, _target, _append_debugger_event), do: state

  @spec maybe_append_after_execution(
          Types.runtime_state(),
          Types.surface_target(),
          Types.runtime_step_result(),
          Types.elm_introspect(),
          append_event_fn(),
          append_debugger_event_fn(),
          (Types.surface_target() -> String.t())
        ) :: Types.runtime_state()
  def maybe_append_after_execution(
        state,
        target,
        execution,
        introspect,
        append_event,
        append_debugger_event,
        source_root_for_target
      )
      when target in [:watch, :companion, :phone] and is_map(execution) do
    followup_count =
      execution
      |> followup_messages()
      |> StepExecution.normalize_followup_messages()
      |> length()

    runtime =
      case Map.get(execution, :runtime) || Map.get(execution, "runtime") do
        value when is_map(value) -> value
        _ -> get_in(state, [target, :model, "runtime_execution"]) || %{}
      end
      |> Map.put("init_cmd_count", meaningful_init_cmd_count(introspect))
      |> Map.put("followup_message_count", followup_count)
      |> Map.put("planned_init_followup_count", followup_count)

    case status_message(runtime) do
      nil ->
        state

      message ->
        state
        |> append_event.(
          "debugger.runtime_status",
          Types.RuntimeStatusEventPayload.from_runtime(
            runtime,
            source_root_for_target.(target),
            message
          )
        )
        |> append_debugger_event.("runtime", target, message, "runtime_status", nil)
    end
  end

  def maybe_append_after_execution(state, _target, _execution, _introspect, _, _, _), do: state

  @spec followup_messages(Types.runtime_step_result()) :: [
          Types.RuntimeStepResult.followup_message()
        ]
  def followup_messages(execution) when is_map(execution) do
    case Map.get(execution, :followup_messages) || Map.get(execution, "followup_messages") do
      messages when is_list(messages) -> messages
      _ -> []
    end
  end

  @spec meaningful_init_cmd_count(Types.elm_introspect()) :: non_neg_integer()
  def meaningful_init_cmd_count(introspect) when is_map(introspect) do
    introspect
    |> IntrospectAccess.cmd_calls("init_cmd_calls")
    |> Enum.count(&meaningful_init_cmd_call?/1)
  end

  def meaningful_init_cmd_count(_), do: 0

  @spec planned_init_followup_count(Types.runtime_step_result(), Types.elm_introspect()) ::
          non_neg_integer()
  def planned_init_followup_count(execution, _introspect) when is_map(execution) do
    execution
    |> followup_messages()
    |> StepExecution.normalize_followup_messages()
    |> length()
  end

  def planned_init_followup_count(_execution, _introspect), do: 0

  @spec status_message(Types.ExecutionRuntimeSnapshot.wire_map()) :: String.t() | nil
  def status_message(runtime) when is_map(runtime) do
    backend = runtime["execution_backend"]
    reason = runtime["external_fallback_reason"]
    followup_count = runtime["followup_message_count"]
    planned_count = runtime["planned_init_followup_count"]
    init_cmd_count = runtime["init_cmd_count"]

    no_planned_followups? =
      cond do
        is_integer(planned_count) -> planned_count == 0
        is_integer(followup_count) -> followup_count == 0
        true -> true
      end

    cond do
      is_binary(reason) and reason != "" ->
        "runtime fallback #{backend || "unknown"}: #{reason}"

      backend in ["fallback_default", "legacy_default", "default"] ->
        "runtime fallback #{backend}"

      init_execution?(runtime) and is_integer(init_cmd_count) and init_cmd_count > 0 and
          no_planned_followups? ->
        "runtime no followups for #{init_cmd_count} init cmd(s)"

      true ->
        nil
    end
  end

  def status_message(_runtime), do: nil

  @spec init_execution?(Types.ExecutionRuntimeSnapshot.wire_map()) :: boolean()
  def init_execution?(runtime) when is_map(runtime) do
    runtime["operation_source"] in ["init_model", nil] and
      runtime["runtime_model_source"] in ["init_model", nil]
  end

  def init_execution?(_runtime), do: false

  @spec meaningful_init_cmd_call?(Types.cmd_call()) :: boolean()
  def meaningful_init_cmd_call?(call) when is_map(call) do
    target = Map.get(call, "target") || Map.get(call, :target) || ""
    name = Map.get(call, "name") || Map.get(call, :name) || ""

    not (target in ["Cmd.none", "Platform.Cmd.none"] or name in ["none", "None", nil]) and
      not init_cmd_status_excluded?(target, name)
  end

  def meaningful_init_cmd_call?(_call), do: false

  @spec init_cmd_status_excluded?(String.t(), String.t()) :: boolean()
  defp init_cmd_status_excluded?(target, name) when is_binary(target) and is_binary(name) do
    String.contains?(target, "Lifecycle") or String.contains?(target, "Sub.batch") or
      name in ["setup", "batch"]
  end

  defp init_cmd_status_excluded?(_target, _name), do: false
end
