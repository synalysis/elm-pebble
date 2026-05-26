defmodule Ide.Debugger.StepApply do
  @moduledoc false

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolRuntimePatch
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:ensure_compile_artifacts) => (map(), Types.surface_target() -> map()),
          required(:hydrate_runtime_model) =>
            (Types.app_model(), String.t() | nil, [String.t()] -> Types.app_model()),
          required(:normalize_message_value) =>
            (map(), Types.surface_target(), Types.subscription_payload() | nil, map() ->
               Types.subscription_payload() | nil),
          required(:normalize_runtime_patch) =>
            (Types.execution_model(), map() -> map()),
          required(:patched_runtime_model_fields) =>
            (Types.app_model() | map() -> [String.t()]),
          required(:preserve_protocol_metadata) => (map(), map() -> map()),
          required(:default_view_tree) => (Types.surface_target() -> map()),
          required(:introspect_for) => (map(), Types.surface_target() -> map()),
          required(:protocol_events_ctx) => (-> map()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:append_runtime_exec) => (map(), Types.surface_target(), map() -> map()),
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:append_debugger_event) =>
            (map(), String.t(), Types.surface_target(), String.t(), String.t() -> map()),
          required(:maybe_append_runtime_status) => (map(), Types.surface_target() -> map()),
          required(:device_data_responses) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:geolocation_response) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:companion_bridge_command_responses) =>
            (map(), Types.surface_target(), String.t(), map(), String.t() -> map()),
          required(:companion_bridge_responses) =>
            (map(), Types.surface_target(), String.t() -> map()),
          required(:static_task_followups) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | nil, String.t() ->
               map()),
          required(:runtime_followups) =>
            (map(), Types.surface_target(), String.t(), String.t(), list() -> map())
        }

  @spec apply(
          map(),
          Types.surface_target(),
          String.t() | nil,
          Types.subscription_payload() | nil,
          String.t() | nil,
          String.t(),
          keyword(),
          ctx()
        ) :: map()
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

    message_value = ctx.normalize_message_value.(state, target, message_value, model)

    step =
      StepInput.from_surface(target, surface, message,
        message_value: message_value,
        trigger: trigger,
        message_source: source_override
      )

    runtime_result = StepExecution.runtime_result(step, update_branches)

    runtime_patch = Map.get(runtime_result, :model_patch, %{})
    runtime_patch = ctx.normalize_runtime_patch.(step.execution_model, runtime_patch)
    runtime_view_tree = Map.get(runtime_result, :view_tree)
    runtime_view_tree = if is_map(runtime_view_tree), do: runtime_view_tree, else: step.view_tree

    preview_runtime_model =
      model
      |> Types.StepExecutionContract.merge_model_patch(runtime_patch)
      |> ctx.hydrate_runtime_model.(message, ctx.patched_runtime_model_fields.(runtime_patch))
      |> RuntimeArtifacts.preview_runtime_model()

    runtime_view_output =
      StepExecution.preferred_view_output(
        Map.get(runtime_result, :view_output),
        Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
      )
      |> then(fn rows ->
        supplemented =
          StepExecution.supplement_parser_runtime_view_output(
            step.execution_model,
            runtime_view_tree,
            preview_runtime_model
          )

        StepExecution.choose_runtime_view_output(supplemented, rows)
      end)

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

    runtime_followups = Map.get(runtime_result, :followup_messages, [])

    protocol_events =
      (runtime_protocol_events ++ command_protocol_events)
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
      |> Map.put("runtime_last_message", message)
      |> Map.put("runtime_message_source", message_source)
      |> Map.put("runtime_message_cursor", next_cursor)
      |> Map.put("runtime_known_messages", known_messages)
      |> Map.put("runtime_update_branches", update_branches)
      |> Map.put("runtime_view_output", runtime_view_output)
      |> Map.update("_debugger_steps", 1, &(&1 + 1))

    rendered_view_tree =
      StepExecution.render_view_after_update(
        runtime_view_tree,
        step.view_tree,
        target,
        message,
        trigger,
        updated_model,
        default_view_tree: ctx.default_view_tree.(target)
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
      |> ctx.append_debugger_event.("update", target, message, message_source)
      |> ctx.maybe_append_runtime_status.(target)
      |> ProtocolRx.apply_side_effects(protocol_events, suppress_protocol_events?, ctx.protocol_rx_ctx.())
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
end
