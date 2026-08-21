defmodule Ide.Debugger.DebuggerContractSnapshot do
  @moduledoc false

  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.CompileContract
  alias ElmEx.DebuggerContract
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeExecutorConfig
  alias Ide.Debugger.RuntimeModelNormalize
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.StepExecutionContract
  alias Ide.Debugger.Types.DebuggerContractEventPayload

  @type executor :: module()

  @type apply_ctx :: %{
          required(:executor) => executor(),
          required(:attach_compile_artifacts) => (Types.runtime_state(),
                                                  Types.surface_target(),
                                                  Types.elm_introspect() ->
                                                    Types.runtime_state()),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:append_debugger_event) => (Types.runtime_state(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t(),
                                               Types.timeline_step_message_value() ->
                                                 Types.runtime_state()),
          required(:runtime_status_after_init) => (Types.runtime_state(),
                                                   Types.surface_target(),
                                                   Types.step_executor_result()
                                                   | Types.wire_map(),
                                                   Types.elm_introspect() ->
                                                     Types.runtime_state()),
          required(:apply_runtime_followups) => (Types.runtime_state(),
                                                 Types.surface_target(),
                                                 String.t(),
                                                 String.t(),
                                                 [Types.runtime_followup_row()] ->
                                                   Types.runtime_state()),
          required(:apply_init_device_data) => (Types.runtime_state(),
                                                Types.surface_target(),
                                                [Types.runtime_followup_row()] ->
                                                  Types.runtime_state()),
          required(:drain_app_message_queue) => (Types.runtime_state(), Types.surface_target() ->
                                                   Types.runtime_state()),
          required(:protocol_rx_ctx) => (-> ProtocolRx.ctx())
        }

  @type merge_ctx :: %{
          required(:apply_snapshot) => apply_ctx(),
          required(:surface_compile) => Ide.Debugger.SurfaceCompileArtifacts.attach_ctx(),
          required(:after_apply) => (Types.runtime_state(), Types.surface_target(), String.t() ->
                                       Types.runtime_state()),
          required(:apply_simulator_settings) => (Types.runtime_state() -> Types.runtime_state()),
          required(:introspect_event_payload) => (Types.elm_introspect(),
                                                  String.t()
                                                  | nil,
                                                  String.t() ->
                                                    DebuggerContractEventPayload.t() | nil)
        }

  @spec elm_introspect?(String.t() | nil, String.t() | nil, String.t()) :: boolean()
  def elm_introspect?(rel_path, source, source_root) do
    source_root in ["watch", "phone"] and is_binary(rel_path) and
      String.ends_with?(rel_path, ".elm") and is_binary(source) and String.trim(source) != ""
  end

  @spec target_key(String.t()) :: :watch | :companion | :phone
  def target_key("watch"), do: :watch
  def target_key("protocol"), do: :companion
  def target_key("phone"), do: :companion
  def target_key(_), do: :watch

  @spec event_worth_logging?(Types.elm_introspect()) :: boolean()
  def event_worth_logging?(ei) when is_map(ei) do
    init = Map.get(ei, "init_model")
    msgs = list_field(ei, "msg_constructors")
    branches = list_field(ei, "update_case_branches")
    vbr = list_field(ei, "view_case_branches")
    ibr = list_field(ei, "init_case_branches")
    sbr = list_field(ei, "subscriptions_case_branches")
    subs = list_field(ei, "subscription_ops")
    icmd = list_field(ei, "init_cmd_ops")
    ucmd = list_field(ei, "update_cmd_ops")
    prts = list_field(ei, "ports")
    imps = list_field(ei, "imported_modules")
    mp = Map.get(ei, "main_program")
    vt = Map.get(ei, "view_tree") || %{}

    params? =
      ["init_params", "update_params", "view_params", "subscriptions_params"]
      |> Enum.any?(fn key ->
        xs = Map.get(ei, key) || []
        is_list(xs) and xs != []
      end)

    port_mod = Map.get(ei, "port_module") == true

    init != nil or msgs != [] or branches != [] or vbr != [] or ibr != [] or sbr != [] or
      subs != [] or icmd != [] or ucmd != [] or prts != [] or imps != [] or is_map(mp) or params? or
      port_mod or StepExecution.introspect_view_usable?(vt, ei)
  end

  @spec merge_from_source(
          Types.runtime_state(),
          String.t() | nil,
          String.t(),
          String.t(),
          merge_ctx()
        ) ::
          {Types.runtime_state(), DebuggerContractEventPayload.t() | nil}
  def merge_from_source(state, rel_path, source, source_root, ctx)
      when is_map(state) and is_binary(source) and is_binary(source_root) and is_map(ctx) do
    if elm_introspect?(rel_path, source, source_root) do
      target = target_key(source_root)

      case resolve_contract(state, target, rel_path, source, source_root, ctx) do
        {:ok, ei} when is_map(ei) ->
          if apply_resolved_contract?(state, target, source_root, rel_path, ei) do
            prepared = ctx.apply_simulator_settings.(state)

            st =
              prepared
              |> apply(ei, target, source, rel_path, ctx.apply_snapshot)
              |> maybe_after_apply(prepared, target, source_root, ctx)

            payload =
              if event_worth_logging?(ei) do
                ctx.introspect_event_payload.(ei, rel_path, source_root)
              else
                nil
              end

            {st, payload}
          else
            {state, nil}
          end

        _ ->
          {state, nil}
      end
    else
      {state, nil}
    end
  end

  @spec resolve_contract(
          Types.runtime_state(),
          Types.surface_target(),
          String.t() | nil,
          String.t(),
          String.t(),
          merge_ctx()
        ) :: {:ok, Types.elm_introspect()} | :error
  defp resolve_contract(state, target, rel_path, source, source_root, ctx)
       when is_map(state) and is_binary(source) and is_binary(source_root) and is_map(ctx) do
    virtual_path = rel_path || "Main.elm"

    cond do
      CompileContract.entrypoint_path?(source_root, rel_path) ->
        case SurfaceCompileArtifacts.debugger_contract_for_reload(
               state,
               target,
               ctx.surface_compile
             ) do
          %{} = contract -> {:ok, contract}
          _ -> analyze_contract_fallback(source, virtual_path)
        end

      true ->
        # Non-entrypoint reloads must not replace the shell entrypoint contract
        # (e.g. Resources.elm / CompanionPreferences.elm analyzed alone).
        # Only apply an isolated file when it is itself a TEA program and no
        # program is bound yet (parser-preview fixtures).
        if existing_program_contract?(state, target) do
          :error
        else
          case analyze_contract_fallback(source, virtual_path) do
            {:ok, ei} ->
              if CompileContract.program_contract?(ei), do: {:ok, ei}, else: :error

            _ ->
              :error
          end
        end
    end
  end

  @spec apply_resolved_contract?(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          Types.elm_introspect()
        ) :: boolean()
  defp apply_resolved_contract?(state, target, source_root, rel_path, ei)
       when is_map(state) and is_map(ei) do
    CompileContract.entrypoint_path?(source_root, rel_path) or
      (CompileContract.program_contract?(ei) and not existing_program_contract?(state, target))
  end

  defp apply_resolved_contract?(_state, _target, _source_root, _rel_path, _ei), do: false

  @spec existing_program_contract?(Types.runtime_state(), Types.surface_target()) :: boolean()
  defp existing_program_contract?(state, target) when is_map(state) do
    state
    |> Map.get(target, %{})
    |> RuntimeArtifacts.introspect()
    |> CompileContract.program_contract?()
  end

  @spec analyze_contract_fallback(String.t(), String.t()) ::
          {:ok, Types.elm_introspect()} | :error
  defp analyze_contract_fallback(source, virtual_path) do
    case CompileContract.analyze_source(source, virtual_path) do
      {:ok, %{"debugger_contract" => contract}} when is_map(contract) -> {:ok, contract}
      _ -> :error
    end
  end

  @spec apply(
          Types.runtime_state(),
          Types.elm_introspect(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          apply_ctx()
        ) :: Types.runtime_state()
  def apply(state, ei, target, source, rel_path, ctx)
      when is_map(ei) and target in [:watch, :companion, :phone] and is_binary(source) and
             is_map(ctx) do
    state = ctx.attach_compile_artifacts.(state, target, ei)
    surface = Map.get(state, target) || %{}
    model = Map.get(surface, :model) || %{}
    shell = RuntimeArtifacts.shell_map(surface)
    view_tree = Map.get(surface, :view_tree) || %{}

    next_shell =
      shell
      |> Map.put("debugger_contract", ei)
      |> Map.put("debugger_contract_version", Map.get(ei, "contract_version"))

    state = put_in(state, [target, :shell], next_shell)

    if can_apply_runtime_init?(state, target) do
      execution_model =
        state
        |> Map.get(target, %{})
        |> RuntimeArtifacts.execution_model()

      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: rel_path || model["last_path"],
          source: source,
          introspect: ei,
          current_model: current_model_for_execution(model),
          current_view_tree: view_tree
        }
        |> Map.merge(RuntimeArtifacts.execution_artifacts(execution_model))
        |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
        |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

      execution = resolve_init_execution(state, request, ctx)

      if init_execution_ok?(execution) do
        finish_successful_init(state, ei, target, source, rel_path, ctx, execution, model)
      else
        record_failed_init(state, target, execution, ctx)
      end
    else
      pending_init_state(state, target)
    end
  end

  # Init when elmx/elmc program artifacts exist, or when tests inject a stub executor
  # that does not need compiled runtime modules.
  defp can_apply_runtime_init?(state, target) do
    SurfaceCompileArtifacts.surface_has_program_runtime_artifacts?(state, target) or
      RuntimeExecutorConfig.module() != Ide.Debugger.RuntimeExecutor
  end

  defp finish_successful_init(state, ei, target, _source, _rel_path, ctx, execution, model) do
    model_patch =
      execution
      |> Map.get(:model_patch, %{})
      |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

    vt = Map.get(ei, "view_tree")
    runtime_vt = Map.get(execution, :view_tree)

    launch_context =
      Map.get(model, "launch_context") ||
        Map.get(state, :launch_context) ||
        %{}

    normalized_patch = RuntimeModelNormalize.patch_values(model, model_patch)

    model =
      model
      |> Map.delete("runtime_execution_error")
      |> Map.put("runtime_execution_mode", "runtime_executed")
      |> then(&StepExecutionContract.merge_model_patch(&1, normalized_patch))
      |> RuntimeSurfaces.merge_launch_context_model(launch_context)
      |> StepExecution.put_runtime_view_output(Map.get(execution, :view_output))
      |> refresh_init_runtime_fingerprints(runtime_vt, ei)

    output_vt = RuntimeViewOutput.tree(model, target)

    state = put_in(state, [target, :model], model)

    parser_view? = DebuggerContract.parser_expression_view?(%{"debugger_contract" => ei})

    state =
      cond do
        StepExecution.introspect_view_usable?(output_vt, ei) and
            (RuntimePreview.has_drawable_output?(model) or
               StepExecution.view_tree_has_draw_ops?(output_vt)) ->
          put_in(state, [target, :view_tree], output_vt)

        StepExecution.introspect_view_usable?(runtime_vt, ei) and
            (RuntimePreview.has_drawable_output?(model) or
               StepExecution.view_tree_has_draw_ops?(runtime_vt)) ->
          put_in(state, [target, :view_tree], runtime_vt)

        parser_view? and StepExecution.introspect_view_usable?(runtime_vt, ei) and
            not RuntimePreview.has_drawable_output?(model) and
            not StepExecution.view_tree_has_draw_ops?(runtime_vt) ->
          put_in(
            state,
            [target, :view_tree],
            RuntimePreview.preview_unavailable_view_tree(
              target,
              "runtime view did not produce drawable output"
            )
          )

        parser_view? and not StepExecution.introspect_view_usable?(output_vt, ei) and
            not StepExecution.introspect_view_usable?(runtime_vt, ei) ->
          put_in(
            state,
            [target, :view_tree],
            RuntimePreview.preview_unavailable_view_tree(
              target,
              "runtime view did not produce drawable output"
            )
          )

        StepExecution.introspect_view_usable?(vt, ei) ->
          put_in(state, [target, :view_tree], vt)

        StepExecution.parser_expression_view_tree?(vt, ei) ->
          put_in(
            state,
            [target, :view_tree],
            RuntimePreview.preview_unavailable_view_tree(
              target,
              "parser view did not produce drawable output"
            )
          )

        true ->
          state
      end

    followups =
      execution
      |> Map.get(:followup_messages)
      |> case do
        messages when is_list(messages) -> messages
        _ -> Map.get(execution, "followup_messages", [])
      end
      |> StepExecution.normalize_followup_messages()

    protocol_events =
      execution
      |> Map.get(:protocol_events)
      |> case do
        events when is_list(events) -> events
        _ -> Map.get(execution, "protocol_events", [])
      end
      |> StepExecution.normalize_protocol_events()

    followups =
      if protocol_events != [] do
        Enum.reject(followups, &RuntimeFollowups.protocol_events_followup?/1)
      else
        followups
      end

    state
    |> ctx.append_event.(
      "debugger.init_in",
      Ide.Debugger.Types.MessageInEventPayload.from_message(
        source_root_for_target(target),
        "init",
        "init"
      )
    )
    |> ctx.append_debugger_event.("init", target, "init", "init", nil)
    |> ctx.runtime_status_after_init.(target, execution, ei)
    |> apply_init_protocol_side_effects(protocol_events, ctx)
    |> ctx.apply_runtime_followups.(target, "init", "init", followups)
    |> ctx.apply_init_device_data.(target, followups)
    |> refresh_watch_launch_context_model(target, launch_context)
    |> ProtocolRx.mark_init_complete(target)
    |> maybe_drain_app_message_queue(state, target, ctx)
    |> flush_init_protocol_deliveries(ctx)
    |> refresh_view_preview_if_unavailable(target)
  end

  @spec pending_init_state(Types.runtime_state(), Types.surface_target()) :: Types.runtime_state()
  defp pending_init_state(state, target) when is_map(state) do
    model = get_in(state, [target, :model]) || %{}

    put_in(
      state,
      [target, :model],
      model
      |> Map.delete("debugger_init_complete")
      |> Map.put("runtime_execution_mode", "pending_artifacts")
    )
  end

  @spec record_failed_init(
          Types.runtime_state(),
          Types.surface_target(),
          Types.step_executor_result() | Types.wire_map(),
          apply_ctx()
        ) :: Types.runtime_state()
  defp record_failed_init(state, target, execution, ctx)
       when is_map(state) and is_map(ctx) do
    detail =
      execution
      |> execution_model_patch()
      |> Map.get("runtime_execution_error") ||
        get_in(execution, [:runtime, "error_detail"]) ||
        get_in(execution, ["runtime", "error_detail"]) ||
        "companion init failed"

    model = get_in(state, [target, :model]) || %{}

    state =
      put_in(
        state,
        [target, :model],
        model
        |> Map.delete("debugger_init_complete")
        |> Map.put("runtime_execution_mode", "error")
        |> Map.put("runtime_execution_error", detail)
      )

    message = "init"
    reason = {:core_ir_execution_failed, detail}

    state
    |> ctx.append_event.(
      "debugger.runtime_exec_error",
      %{
        "execution_status" => "error",
        "error_code" => "runtime_exec_error",
        "error_detail" => execution_error_detail(reason),
        "message" => message,
        "source_root" => source_root_for_target(target)
      }
    )
    |> ctx.append_debugger_event.("runtime_exec_error", target, message, "core_ir", nil)
  end

  @spec init_execution_ok?(Types.step_executor_result() | Types.wire_map()) :: boolean()
  defp init_execution_ok?(execution) when is_map(execution) do
    patch = execution_model_patch(execution)
    runtime = Map.get(execution, :runtime) || Map.get(execution, "runtime") || %{}

    is_map(Map.get(patch, "runtime_model")) and
      not Map.has_key?(patch, "runtime_execution_error") and
      Map.get(runtime, "execution_status") != "error" and
      Map.get(runtime, "error_code") != "runtime_exec_error"
  end

  @spec execution_model_patch(Types.step_executor_result() | Types.wire_map()) :: Types.wire_map()
  defp execution_model_patch(execution) when is_map(execution) do
    case Map.get(execution, :model_patch) || Map.get(execution, "model_patch") do
      patch when is_map(patch) -> patch
      _ -> %{}
    end
  end

  @spec apply_init_protocol_side_effects(
          Types.runtime_state(),
          [Types.protocol_timeline_event()],
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_init_protocol_side_effects(state, [], _ctx), do: state

  defp apply_init_protocol_side_effects(state, protocol_events, ctx)
       when is_list(protocol_events) and is_map(ctx) do
    ProtocolRx.apply_side_effects(state, protocol_events, false, ctx.protocol_rx_ctx.())
  end

  defp apply_init_protocol_side_effects(state, _protocol_events, _ctx), do: state

  @spec flush_init_protocol_deliveries(Types.runtime_state(), apply_ctx()) ::
          Types.runtime_state()
  defp flush_init_protocol_deliveries(state, ctx) when is_map(ctx) do
    ProtocolRx.flush_inline_protocol_deliveries(state, ctx.protocol_rx_ctx.())
  end

  @spec refresh_watch_launch_context_model(
          Types.runtime_state(),
          Types.surface_target(),
          Types.launch_context()
        ) :: Types.runtime_state()
  defp refresh_watch_launch_context_model(state, :watch, launch_context)
       when is_map(state) and is_map(launch_context) do
    update_in(state, [:watch, :model], fn model ->
      RuntimeSurfaces.merge_launch_context_model(model, launch_context)
    end)
  end

  defp refresh_watch_launch_context_model(state, _target, _launch_context), do: state

  @spec refresh_init_runtime_fingerprints(
          Types.app_model(),
          Types.view_output_tree() | nil,
          Types.elm_introspect()
        ) :: Types.app_model()
  defp refresh_init_runtime_fingerprints(model, runtime_vt, ei)
       when is_map(model) and is_map(ei) do
    runtime_model =
      case Map.get(model, "runtime_model") do
        %{} = inner -> inner
        _ -> %{}
      end

    view_tree = if is_map(runtime_vt), do: runtime_vt, else: %{}

    model
    |> Map.put_new("runtime_model_source", "init_model")
    |> then(fn next ->
      if is_map(Map.get(ei, "view_tree")) do
        Map.put(next, "runtime_view_tree_source", "parser_view_tree")
      else
        next
      end
    end)
    |> StepExecution.refresh_runtime_fingerprints(runtime_model, view_tree)
  end

  @spec refresh_view_preview_if_unavailable(Types.runtime_state(), Types.surface_target()) ::
          Types.runtime_state()
  defp refresh_view_preview_if_unavailable(state, target) when is_map(state) do
    surface = Map.get(state, target) || %{}
    view_tree = Map.get(surface, :view_tree) || %{}
    type = Map.get(view_tree, :type) || Map.get(view_tree, "type")
    ei = get_in(surface, [:shell, "debugger_contract"]) || %{}

    if type == "previewUnavailable" and
         not DebuggerContract.parser_expression_view?(%{"debugger_contract" => ei}) do
      RuntimePreview.refresh_for_target(state, target, RuntimeExecutor)
    else
      state
    end
  end

  defp maybe_after_apply(state, original_state, target, source_root, ctx) do
    if BootstrapInit.defer_surface_effects?(original_state) do
      state
    else
      ctx.after_apply.(state, target, source_root)
    end
  end

  @spec resolve_init_execution(Types.runtime_state(), Types.wire_map(), apply_ctx()) ::
          Types.step_executor_result() | Types.wire_map()
  defp resolve_init_execution(_state, request, ctx) do
    case ctx.executor.execute(request) do
      {:ok, payload} when is_map(payload) ->
        payload

      {:error, reason} ->
        detail = execution_error_detail(reason)

        %{
          model_patch: %{
            "runtime_model" => %{},
            "runtime_execution_error" => detail
          },
          view_tree: nil,
          runtime: %{
            "execution_status" => "error",
            "error_code" => "runtime_exec_error",
            "error_detail" => detail
          }
        }
    end
  end

  defp maybe_drain_app_message_queue(state, original_state, target, ctx) do
    if BootstrapInit.defer_surface_effects?(original_state) do
      state
    else
      ctx.drain_app_message_queue.(state, target)
    end
  end

  @spec current_model_for_execution(Types.execution_model()) :: Types.execution_model()
  def current_model_for_execution(model) when is_map(model),
    do: Map.delete(model, "runtime_model")

  def current_model_for_execution(_model), do: %{}

  @spec source_root_for_target(Types.surface_target()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"

  defp list_field(ei, key) do
    case Map.get(ei, key) do
      xs when is_list(xs) -> xs
      _ -> []
    end
  end

  @spec execution_error_detail(Types.execution_error()) :: String.t()
  defp execution_error_detail({:core_ir_execution_failed, {:missing_elmx_manifest, detail}})
       when is_binary(detail),
       do: detail

  defp execution_error_detail({:core_ir_execution_failed, :missing_elmx_manifest}),
    do: "missing elmx manifest — recompile watch/phone and reload the debugger"

  defp execution_error_detail({:core_ir_execution_failed, reason}),
    do: execution_error_detail(reason)

  defp execution_error_detail(reason), do: inspect(reason, limit: 200)
end
