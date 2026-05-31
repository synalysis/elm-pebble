defmodule Ide.Debugger.ElmIntrospectSnapshot do
  @moduledoc false

  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ProtocolRx
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimePreview
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.ElmIntrospectEventPayload

  @type executor :: module()

  @type apply_ctx :: %{
          required(:executor) => executor(),
          required(:attach_compile_artifacts) =>
            (Types.runtime_state(), Types.surface_target(), Types.elm_introspect() ->
               Types.runtime_state()),
          required(:hydrate_runtime_model) =>
            (Types.app_model(), String.t() | nil, [String.t()] -> Types.app_model()),
          required(:append_event) =>
            (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:append_debugger_event) =>
            (Types.runtime_state(), String.t(), Types.surface_target(), String.t(), String.t(),
             Types.timeline_step_message_value() -> Types.runtime_state()),
          required(:runtime_status_after_init) =>
            (Types.runtime_state(), Types.surface_target(), Types.step_executor_result() | map(),
             Types.elm_introspect() -> Types.runtime_state()),
          required(:apply_runtime_followups) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t(),
             [Types.runtime_followup_row()] -> Types.runtime_state()),
          required(:drain_app_message_queue) =>
            (Types.runtime_state(), Types.surface_target() -> Types.runtime_state())
        }

  @type merge_ctx :: %{
          required(:apply_snapshot) => apply_ctx(),
          required(:after_apply) =>
            (Types.runtime_state(), Types.surface_target(), String.t() -> Types.runtime_state()),
          required(:apply_simulator_settings) => (Types.runtime_state() -> Types.runtime_state()),
          required(:introspect_event_payload) =>
            (Types.elm_introspect(), String.t() | nil, String.t() -> ElmIntrospectEventPayload.t() | nil)
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

  @spec merge_from_source(Types.runtime_state(), String.t() | nil, String.t(), String.t(), merge_ctx()) ::
          {Types.runtime_state(), ElmIntrospectEventPayload.t() | nil}
  def merge_from_source(state, rel_path, source, source_root, ctx)
      when is_map(state) and is_binary(source) and is_binary(source_root) and is_map(ctx) do
    if elm_introspect?(rel_path, source, source_root) do
      case ElmIntrospect.analyze_source(source, rel_path || "Main.elm") do
        {:ok, %{"elm_introspect" => ei}} ->
          target = target_key(source_root)

          st =
            state
            |> apply(ei, target, source, rel_path, ctx.apply_snapshot)
            |> maybe_after_apply(state, target, source_root, ctx)

          payload =
            if event_worth_logging?(ei) do
              ctx.introspect_event_payload.(ei, rel_path, source_root)
            else
              nil
            end

          {ctx.apply_simulator_settings.(st), payload}

        _ ->
          {state, nil}
      end
    else
      {state, nil}
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
      when is_map(ei) and target in [:watch, :companion, :phone] and is_binary(source) and is_map(ctx) do
    state = ctx.attach_compile_artifacts.(state, target, ei)
    surface = Map.get(state, target) || %{}
    model = Map.get(surface, :model) || %{}
    shell = RuntimeArtifacts.shell_map(surface)
    view_tree = Map.get(surface, :view_tree) || %{}
    execution_model = RuntimeArtifacts.execution_model(surface)

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

    model_patch =
      execution
      |> Map.get(:model_patch, %{})
      |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

    model =
      model
      |> Map.put("elm_executor_mode", "runtime_executed")
      |> Map.merge(model_patch)
      |> StepExecution.put_runtime_view_output(Map.get(execution, :view_output))
      |> ctx.hydrate_runtime_model.(nil, [])

    next_shell = Map.put(shell, "elm_introspect", ei)

    vt = Map.get(ei, "view_tree")
    runtime_vt = Map.get(execution, :view_tree)
    output_vt = RuntimeViewOutput.tree(model, target)

    state =
      state
      |> put_in([target, :model], model)
      |> put_in([target, :shell], next_shell)

    parser_view? = ElmIntrospect.parser_expression_view?(%{"elm_introspect" => ei})

    state =
      cond do
        StepExecution.introspect_view_usable?(output_vt, ei) ->
          put_in(state, [target, :view_tree], output_vt)

        StepExecution.introspect_view_usable?(runtime_vt, ei) and RuntimePreview.has_drawable_output?(model) ->
          put_in(state, [target, :view_tree], runtime_vt)

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
    |> ctx.apply_runtime_followups.(target, "init", "init", followups)
    |> ProtocolRx.mark_init_complete(target)
    |> maybe_drain_app_message_queue(state, target, ctx)
  end

  defp maybe_after_apply(state, original_state, target, source_root, ctx) do
    if BootstrapInit.defer_surface_effects?(original_state) do
      state
    else
      ctx.after_apply.(state, target, source_root)
    end
  end

  @spec resolve_init_execution(Types.runtime_state(), map(), apply_ctx()) ::
          Types.step_executor_result() | map()
  defp resolve_init_execution(_state, request, ctx) do
    case ctx.executor.execute(request) do
      {:ok, payload} when is_map(payload) ->
        payload

      {:error, reason} ->
        %{
          model_patch: %{
            "runtime_model" => %{},
            "runtime_execution_error" => inspect(reason, limit: 50)
          },
          view_tree: nil,
          runtime: %{
            "execution_status" => "error",
            "error_code" => "core_ir_init_failed",
            "error_detail" => inspect(reason, limit: 50)
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
  def current_model_for_execution(model) when is_map(model), do: Map.delete(model, "runtime_model")
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
end
