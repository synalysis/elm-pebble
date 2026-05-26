defmodule Ide.Debugger.RuntimePreview do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Types

  @type executor :: module()

  @spec refresh_from_artifacts(map(), executor()) :: map()
  def refresh_from_artifacts(state, executor) when is_map(state) do
    Enum.reduce([:watch, :companion, :phone], state, fn target, acc ->
      refresh_for_target(acc, target, executor)
    end)
  end

  @spec refresh_for_target(map(), :watch | :companion | :phone, executor()) :: map()
  def refresh_for_target(state, target, executor)
      when is_map(state) and target in [:watch, :companion, :phone] do
    surface = state |> Map.get(target, %{}) |> RuntimeArtifacts.normalize_surface()
    model = Map.get(surface, :model) || %{}
    execution_model = RuntimeArtifacts.execution_model(surface)
    introspect = RuntimeArtifacts.introspect(execution_model)
    artifacts = RuntimeArtifacts.execution_artifacts(execution_model)

    if is_map(introspect) and artifacts != %{} do
      view_tree = Map.get(surface, :view_tree) || %{}

      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: Map.get(model, "last_path"),
          source: "",
          introspect: introspect,
          current_model: model,
          current_view_tree: view_tree
        }
        |> Map.merge(artifacts)
        |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
        |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

      case executor.execute(request) do
        {:ok, payload} when is_map(payload) ->
          model_patch =
            payload
            |> Map.get(:model_patch, %{})
            |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

          runtime_view_output =
            StepExecution.preferred_view_output(
              Map.get(payload, :view_output),
              Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output)
            )

          next_model =
            model
            |> Map.put("elm_executor_mode", "runtime_executed")
            |> Map.merge(model_patch)
            |> StepExecution.put_runtime_view_output(runtime_view_output)

          next_state = put_in(state, [target, :model], next_model)
          ei = RuntimeArtifacts.require_introspect(next_model)

          runtime_view_tree =
            case RuntimeViewOutput.tree(next_model, target) do
              %{} = output_tree ->
                if StepExecution.introspect_view_usable?(output_tree, ei), do: output_tree, else: nil

              _ ->
                nil
            end
            |> case do
              %{} = tree ->
                tree

              _ ->
                choose_view_tree(
                  Map.get(payload, :view_tree),
                  view_tree,
                  view_tree,
                  runtime_view_output,
                  ei
                )
            end

          if StepExecution.introspect_view_usable?(runtime_view_tree, ei) do
            put_in(next_state, [target, :view_tree], runtime_view_tree)
          else
            next_state
          end

        _ ->
          state
      end
    else
      supplement_without_executor(state, target, execution_model, introspect)
    end
  end

  @spec render_for_debugger_entry(map() | nil, map() | nil, :watch | :companion | :phone, executor()) ::
          map() | nil
  def render_for_debugger_entry(nil, _latest_runtime, _target, _executor), do: nil

  def render_for_debugger_entry(snapshot_runtime, latest_runtime, target, executor)
      when is_map(snapshot_runtime) and is_map(latest_runtime) and target in [:watch, :companion, :phone] do
    render_for_debugger(snapshot_runtime, latest_runtime, target, executor)
  end

  def render_for_debugger_entry(snapshot_runtime, _latest_runtime, _target, _executor),
    do: snapshot_runtime

  @spec render_for_debugger(map(), map(), :watch | :companion | :phone, executor()) :: map()
  def render_for_debugger(snapshot_runtime, latest_runtime, target, executor)
      when is_map(snapshot_runtime) and is_map(latest_runtime) and
             target in [:watch, :companion, :phone] do
    snapshot_surface = RuntimeArtifacts.normalize_surface(snapshot_runtime)
    latest_surface = RuntimeArtifacts.normalize_surface(latest_runtime)

    snapshot_model = Map.get(snapshot_surface, :model) || %{}
    latest_model = Map.get(latest_surface, :model) || %{}

    app_model = merge_latest_render_inputs(snapshot_model, latest_model)

    execution_model =
      RuntimeArtifacts.shell_map(latest_surface)
      |> Map.merge(RuntimeArtifacts.shell_map(snapshot_surface))
      |> Map.merge(RuntimeArtifacts.strip_shell_artifacts(app_model))

    introspect = RuntimeArtifacts.introspect(execution_model)
    artifacts = RuntimeArtifacts.execution_artifacts(execution_model)

    view_tree =
      Map.get(snapshot_runtime, :view_tree) || Map.get(snapshot_runtime, "view_tree") || %{}

    latest_view_tree =
      Map.get(latest_runtime, :view_tree) || Map.get(latest_runtime, "view_tree") || %{}

    if is_map(introspect) and artifacts != %{} do
      request =
        %{
          source_root: source_root_for_target(target),
          rel_path: Map.get(app_model, "last_path"),
          source: "",
          introspect: introspect,
          current_model: app_model,
          current_view_tree: view_tree
        }
        |> Map.merge(artifacts)
        |> RuntimeArtifacts.put_vector_resource_indices_on_request(execution_model)
        |> RuntimeArtifacts.put_bitmap_resource_indices_on_request(execution_model)

      case executor.execute(request) do
        {:ok, payload} when is_map(payload) ->
          model_patch =
            payload
            |> Map.get(:model_patch, %{})
            |> then(fn patch -> if is_map(patch), do: patch, else: %{} end)

          runtime_view_output =
            StepExecution.preferred_view_output(
              Map.get(payload, :view_output),
              Map.get(app_model, "runtime_view_output") || Map.get(app_model, :runtime_view_output)
            )

          next_model =
            app_model
            |> Map.put("elm_executor_mode", "runtime_executed")
            |> Map.merge(model_patch)
            |> StepExecution.put_runtime_view_output(runtime_view_output)

          runtime_view_tree =
            choose_view_tree(
              Map.get(payload, :view_tree),
              latest_view_tree,
              view_tree,
              runtime_view_output,
              RuntimeArtifacts.require_introspect(next_model)
            )

          snapshot_runtime
          |> Map.put(:model, next_model)
          |> put_debugger_view_tree(runtime_view_tree)

        _ ->
          snapshot_runtime
      end
    else
      snapshot_runtime
    end
  end

  @spec merge_latest_render_inputs(map(), map()) :: map()
  def merge_latest_render_inputs(snapshot_model, latest_model)
      when is_map(snapshot_model) and is_map(latest_model) do
    Enum.reduce(
      ["runtime_view_output", "last_path"],
      snapshot_model,
      fn key, acc ->
        case Map.get(latest_model, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end
    )
  end

  @spec put_debugger_view_tree(map(), map() | nil) :: map()
  def put_debugger_view_tree(runtime, runtime_view_tree) when is_map(runtime) do
    ei = RuntimeArtifacts.introspect(runtime) || %{}

    if StepExecution.introspect_view_usable?(runtime_view_tree, ei) do
      Map.put(runtime, :view_tree, runtime_view_tree)
    else
      runtime
    end
  end

  @spec choose_view_tree(
          map() | nil,
          map() | nil,
          map() | nil,
          Types.runtime_view_nodes(),
          Types.elm_introspect()
        ) :: map() | nil
  def choose_view_tree(runtime_view_tree, latest_view_tree, snapshot_view_tree, _view_output, ei)
      when is_map(ei) do
    cond do
      StepExecution.concrete_runtime_view_tree?(runtime_view_tree, ei) ->
        runtime_view_tree

      StepExecution.concrete_runtime_view_tree?(latest_view_tree, ei) and
          StepExecution.parser_expression_view_tree?(runtime_view_tree, ei) ->
        latest_view_tree

      true ->
        if StepExecution.concrete_runtime_view_tree?(snapshot_view_tree, ei),
          do: snapshot_view_tree,
          else: nil
    end
  end

  @spec supplement_without_executor(map(), :watch | :companion | :phone, map(), map() | nil) :: map()
  def supplement_without_executor(state, target, execution_model, introspect)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(execution_model) and
             is_map(introspect) do
    model = get_in(state, [target, :model]) || %{}
    runtime_model = RuntimeArtifacts.preview_runtime_model(model)

    view_output =
      StepExecution.supplement_parser_runtime_view_output(
        execution_model,
        Map.get(introspect, "view_tree") || %{},
        runtime_model
      )

    if view_output == [] do
      state
    else
      put_in(state, [target, :model, "runtime_view_output"], view_output)
    end
  end

  def supplement_without_executor(state, _target, _execution_model, _introspect), do: state

  @spec has_drawable_output?(map()) :: boolean()
  def has_drawable_output?(model) when is_map(model) do
    model
    |> Map.get("runtime_view_output", [])
    |> List.wrap()
    |> Enum.any?(fn
      %{"kind" => kind} when is_binary(kind) and kind not in ["clear", ""] -> true
      %{kind: kind} when is_binary(kind) and kind not in ["clear", ""] -> true
      _ -> false
    end)
  end

  @spec preview_unavailable_view_tree(:watch | :companion | :phone, String.t()) :: map()
  def preview_unavailable_view_tree(target, reason) do
    %{
      "type" => "previewUnavailable",
      "label" => reason,
      "target" => source_root_for_target(target),
      "children" => []
    }
  end

  @spec source_root_for_target(Types.surface_target()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"
end
