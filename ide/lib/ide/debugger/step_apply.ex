defmodule Ide.Debugger.StepApply do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRuntimePatch
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.Types

  @phone_to_watch_triggers ~w(phone_to_watch on_phone_to_watch)

  # Callback fields use map() so Dialyzer accepts ctx maps built via partial application
  # in StepApplyCallbacks; named implementations there keep precise @specs.
  @type ctx :: %{
          required(:ensure_compile_artifacts) => (map(), Types.surface_target() -> map()),
          required(:hydrate_runtime_model) => (map(), String.t() | nil, [String.t()] -> map()),
          required(:normalize_message_value) => (map(),
                                                 Types.surface_target(),
                                                 Types.subscription_payload()
                                                 | nil,
                                                 map() ->
                                                   Types.subscription_payload() | nil),
          required(:normalize_runtime_patch) => (map(), map() -> map()),
          required(:patched_runtime_model_fields) => (map() -> [String.t()]),
          required(:preserve_protocol_metadata) => (map(), map() -> map()),
          required(:default_view_tree) => (Types.surface_target() -> map()),
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:append_runtime_exec) => (map(), Types.surface_target(), map() -> map()),
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) => (map(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t(),
                                               map()
                                               | nil ->
                                                 map()),
          required(:maybe_append_runtime_status) => (map(), Types.surface_target() -> map()),
          required(:device_data_responses) => (map(),
                                               Types.surface_target(),
                                               String.t(),
                                               map(),
                                               String.t() ->
                                                 map()),
          required(:geolocation_response) => (map(),
                                              Types.surface_target(),
                                              String.t(),
                                              map(),
                                              String.t() ->
                                                map()),
          required(:companion_bridge_command_responses) => (map(),
                                                            Types.surface_target(),
                                                            String.t(),
                                                            map(),
                                                            String.t() ->
                                                              map()),
          required(:companion_bridge_responses) => (map(), Types.surface_target() -> map()),
          required(:static_task_followups) => (map(),
                                               Types.surface_target(),
                                               String.t(),
                                               Types.subscription_payload()
                                               | nil,
                                               String.t() ->
                                                 map()),
          required(:runtime_followups) => (map(),
                                           Types.surface_target(),
                                           String.t(),
                                           String.t(),
                                           list() ->
                                             map())
        }

  @spec apply(
          map(),
          Types.surface_target(),
          String.t() | nil,
          term(),
          String.t() | nil,
          String.t(),
          keyword(),
          map()
        ) :: any()
  def apply(state, target, requested_message, message_value, source_override, trigger, opts, ctx)
      when target in [:watch, :companion, :phone] and is_list(opts) and is_map(ctx) do
    suppress_protocol_events? = Keyword.get(opts, :suppress_protocol_events, false)
    state = ctx.ensure_compile_artifacts.(state, target)
    surface = Surface.from_state(state, target)

    model =
      surface
      |> Surface.app_model()
      |> ctx.hydrate_runtime_model.(nil, [])

    surface = Surface.put_app_model(surface, model)
    execution_model = Surface.execution_model(surface)

    {message, msg_source, known_messages, update_branches, next_cursor} =
      StepExecution.resolve_message(execution_model, requested_message)

    timeline_message_value = timeline_message_value(requested_message, message, message_value)
    message_value = ctx.normalize_message_value.(state, target, message_value, model)

    step =
      StepInput.from_surface(target, surface, message,
        message_value: message_value,
        trigger: trigger,
        message_source: source_override
      )

    case StepExecution.runtime_result(step, update_branches) do
      {:error, reason} ->
        record_step_execution_error(state, target, message, reason, ctx)

      {:ok, runtime_result} ->
        apply_runtime_result(
          state,
          target,
          step,
          model,
          runtime_result,
          message,
          msg_source,
          known_messages,
          update_branches,
          next_cursor,
          requested_message,
          message_value,
          timeline_message_value,
          source_override,
          trigger,
          suppress_protocol_events?,
          ctx
        )
    end
  end

  defp apply_runtime_result(
         state,
         target,
         step,
         model,
         runtime_result,
         message,
         msg_source,
         known_messages,
         update_branches,
         next_cursor,
         _requested_message,
         message_value,
         timeline_message_value,
         source_override,
         trigger,
         suppress_protocol_events?,
         ctx
       ) do
    runtime_patch = Map.get(runtime_result, :model_patch, %{})
    runtime_patch = ctx.normalize_runtime_patch.(step.execution_model, runtime_patch)
    runtime_view_tree = Map.get(runtime_result, :view_tree)
    runtime_view_tree = if is_map(runtime_view_tree), do: runtime_view_tree, else: step.view_tree

    message_source = source_override || msg_source

    runtime_protocol_events = Map.get(runtime_result, :protocol_events, [])

    model_for_protocol =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> ctx.hydrate_runtime_model.(message, [])

    command_protocol_events =
      cond do
        runtime_protocol_events == [] ->
          ProtocolEvents.events_for_model_commands(
            state,
            model_for_protocol,
            target,
            message,
            message_value,
            ctx.protocol_events_ctx.()
          )

        true ->
          []
      end

    phone_to_watch_protocol_events =
      phone_to_watch_delivery_protocol_events(target, message, message_value, trigger)

    runtime_followups = Map.get(runtime_result, :followup_messages, [])

    protocol_events =
      (runtime_protocol_events ++ command_protocol_events ++ phone_to_watch_protocol_events)
      |> ProtocolEvents.normalize_from_schema(state, ctx.protocol_events_ctx.())
      |> ProtocolEvents.enrich(trigger, message_source)

    introspect = ctx.introspect_for.(state, target)

    protocol_runtime_patch =
      ProtocolRuntimePatch.runtime_patch_for_message(introspect, message_value)

    updated_model =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> ProtocolRuntimePatch.merge_model_patch(
        protocol_runtime_patch,
        ctx.introspect_for.(state, target)
      )
      |> ctx.hydrate_runtime_model.(message, ctx.patched_runtime_model_fields.(runtime_patch))
      |> then(fn m -> ctx.preserve_protocol_metadata.(m, model) end)

    runtime_view_output =
      StepExecution.resolve_runtime_view_output(
        step.execution_model,
        runtime_view_tree,
        updated_model,
        Map.get(runtime_result, :view_output)
      )

    updated_model =
      updated_model
      |> Map.put("runtime_last_message", message)
      |> Map.put("runtime_message_source", message_source)
      |> Map.put("runtime_message_cursor", next_cursor)
      |> Map.put("runtime_known_messages", known_messages)
      |> Map.put("runtime_update_branches", update_branches)
      |> Map.put("runtime_view_output", runtime_view_output)
      |> StepExecution.tag_runtime_view_output_capture()
      |> Map.update("_debugger_steps", 1, &(&1 + 1))

    runtime_model = Map.get(updated_model, "runtime_model") || %{}

    updated_model =
      StepExecution.refresh_runtime_fingerprints(
        updated_model,
        runtime_model,
        runtime_view_tree || %{}
      )

    rendered_view_tree =
      StepExecution.render_view_after_update(
        runtime_view_tree,
        step.view_tree,
        target,
        message,
        trigger,
        updated_model,
        default_view_tree: ctx.default_view_tree.(target),
        execution_model: step.execution_model
      )

    updated_state =
      state
      |> Surface.put_in_state(
        target,
        step.surface
        |> Surface.put_app_model(updated_model)
        |> Surface.put_view_tree(rendered_view_tree)
        |> Surface.put_last_message(message)
      )

    root =
      updated_state
      |> get_in([target, :view_tree, "type"])
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "simulated-root"
      end

    target_name = ctx.source_root_for_target.(target)

    updated_state =
      updated_state
      |> ctx.append_runtime_exec.(target, %{
        trigger: trigger,
        message: message,
        message_source: message_source
      })
      |> ctx.append_event.(
        "debugger.update_in",
        Ide.Debugger.Types.MessageInEventPayload.from_message(
          target_name,
          message,
          message_source
        )
      )
      |> ctx.append_debugger_event.(
        "update",
        target,
        RuntimeModelMessages.wire_constructor(message) || message,
        message_source,
        timeline_message_value
      )
      |> ctx.maybe_append_runtime_status.(target)
      |> ProtocolRx.apply_side_effects(
        protocol_events,
        suppress_protocol_events?,
        ctx.protocol_rx_ctx.()
      )
      |> ctx.append_event.(
        "debugger.view_render",
        Ide.Debugger.Types.ViewRenderEventPayload.from_render(target_name, root)
      )

    updated_state =
      ctx.device_data_responses.(
        updated_state,
        target,
        message,
        updated_model,
        message_source
      )
      |> ctx.geolocation_response.(target, message, updated_model, message_source)
      |> ctx.companion_bridge_command_responses.(
        target,
        message,
        updated_model,
        message_source
      )
      |> ctx.companion_bridge_responses.(target, message_source)
      |> ctx.static_task_followups.(target, message, message_value, message_source)

    ctx.runtime_followups.(
      updated_state,
      target,
      message,
      message_source,
      runtime_followups
    )
  end

  @spec timeline_message_value(
          String.t() | nil,
          String.t(),
          Types.timeline_step_message_value()
        ) :: Types.timeline_step_message_value()
  defp phone_to_watch_delivery_protocol_events(:watch, message, message_value, trigger)
       when trigger in @phone_to_watch_triggers and is_binary(message) and message != "" do
    ProtocolEvents.tx_rx_events("companion", "watch", message, trigger, message_value)
  end

  defp phone_to_watch_delivery_protocol_events(_target, _message, _message_value, _trigger),
    do: []

  defp timeline_message_value(requested_message, message, message_value) do
    case TimelineMessage.message_value_for_step(requested_message || "", message_value) do
      {_, value} when not is_nil(value) ->
        value

      _ ->
        case TimelineMessage.message_value_for_step(message, message_value) do
          {_, value} when not is_nil(value) -> value
          _ -> message_value
        end
    end
  end

  @spec record_step_execution_error(
          map(),
          Types.surface_target(),
          String.t(),
          Types.execution_error(),
          ctx()
        ) :: map()
  defp record_step_execution_error(state, target, message, reason, ctx) do
    detail = inspect(reason, limit: 12, printable_limit: 256)

    payload = %{
      "execution_status" => "error",
      "error_code" => execution_error_code(reason),
      "error_detail" => detail,
      "message" => message,
      "source_root" => ctx.source_root_for_target.(target)
    }

    state
    |> ctx.append_event.("debugger.runtime_exec_error", payload)
    |> ctx.append_debugger_event.(
      "runtime_exec_error",
      target,
      message,
      "core_ir",
      nil
    )
    |> Map.put(:last_execution_error, payload)
  end

  @spec execution_error_code(Types.execution_error()) :: String.t()
  defp execution_error_code({:core_ir_execution_failed, reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp execution_error_code({:core_ir_execution_failed, reason}), do: inspect(reason, limit: 50)

  defp execution_error_code(reason), do: inspect(reason, limit: 50)
end
