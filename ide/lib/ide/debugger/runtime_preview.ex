defmodule Ide.Debugger.RuntimePreview do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepExecution
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type executor :: module()

  @spec refresh_from_artifacts(Types.runtime_state(), executor()) :: Types.runtime_state()
  def refresh_from_artifacts(state, executor) when is_map(state) do
    Enum.reduce([:watch, :companion, :phone], state, fn target, acc ->
      refresh_for_target(acc, target, executor)
    end)
  end

  @spec refresh_for_target(Types.runtime_state(), Types.surface_target(), executor()) ::
          Types.runtime_state()
  def refresh_for_target(state, target, _executor)
      when is_map(state) and target in [:watch, :companion, :phone] do
    surface =
      state
      |> Map.get(target, %{})
      |> RuntimeArtifacts.normalize_surface()
      |> enrich_surface_resource_indices(state)

    case render_view_from_surface(surface, target) do
      %{} = runtime -> put_in(state, [target], runtime)
      _ -> state
    end
  end

  @spec render_for_debugger_entry(
          Surface.surface_map() | nil,
          Surface.surface_map() | nil,
          Types.surface_target(),
          executor()
        ) :: Surface.surface_map() | nil
  def render_for_debugger_entry(nil, _latest_runtime, _target, _executor), do: nil

  def render_for_debugger_entry(surface_runtime, _latest_runtime, target, _executor)
      when is_map(surface_runtime) and target in [:watch, :companion, :phone] do
    render_view_from_surface(surface_runtime, target)
  end

  def render_for_debugger_entry(surface_runtime, _latest_runtime, _target, _executor),
    do: surface_runtime

  @spec render_for_debugger(
          Surface.surface_map(),
          Surface.surface_map(),
          Types.surface_target(),
          executor()
        ) :: Surface.surface_map()
  def render_for_debugger(surface_runtime, _latest_runtime, target, _executor)
      when is_map(surface_runtime) and target in [:watch, :companion, :phone] do
    render_view_from_surface(surface_runtime, target) || surface_runtime
  end

  @doc """
  Derives drawable preview rows and view tree from the surface `model` only.

  Runs the Elm `view` against the current runtime model via Core IR when available.
  Does not re-run `update` or `init` through the executor.
  """
  @spec render_view_from_surface(Surface.surface_map(), Types.surface_target()) ::
          Surface.surface_map() | nil
  def render_view_from_surface(surface_runtime, target)
      when is_map(surface_runtime) and target in [:watch, :companion, :phone] do
    surface = RuntimeArtifacts.normalize_surface(surface_runtime)
    model = Map.get(surface, :model) || %{}
    execution_model = RuntimeArtifacts.execution_model(surface)
    introspect = RuntimeArtifacts.introspect(execution_model)

    if is_map(introspect) and map_size(introspect) > 0 do
      surface_view_tree = Map.get(surface, :view_tree) || %{}

      preview_model =
        model
        |> RuntimeArtifacts.preview_runtime_model()
        |> Map.merge(StepExecution.screen_dimensions_for_view_preview(execution_model))
        |> preview_model_for_message(Map.get(model, "runtime_last_message"))

      stored_rows =
        Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

      ei = RuntimeArtifacts.require_introspect(execution_model)

      executor_refresh =
        if force_executor_view_preview?(surface_view_tree, execution_model, target) do
          case StepExecution.executor_view_preview(execution_model, model, target) do
            {:ok, preview} -> {:ok, preview}
            :error -> :skip
          end
        else
          StepExecution.maybe_executor_view_preview(
            execution_model,
            model,
            target,
            stored_rows
          )
        end

      preview =
        case executor_refresh do
          {:ok, fresh} ->
            fresh

          :skip ->
            surface_tree_for_preview =
              if StepExecution.placeholder_view_tree?(surface_view_tree),
                do: %{},
                else: surface_view_tree

            preview_from_surface_trees(
              surface_tree_for_preview,
              preview_model,
              stored_rows,
              ei,
              execution_model,
              model,
              target
            )
        end

      derived_view_tree = Map.get(preview, :view_tree)

      preview =
        if StepExecution.placeholder_view_tree?(derived_view_tree) and
             RuntimeArtifacts.versioned_elmx_artifacts?(execution_model) and
             target == :watch do
          case StepExecution.executor_view_preview(execution_model, model, target) do
            {:ok, fresh} -> fresh
            :error -> preview
          end
        else
          preview
        end

      view_output = Map.get(preview, :view_output) || []
      derived_view_tree = Map.get(preview, :view_tree)
      preview_error = Map.get(preview, :preview_error)

      model =
        model
        |> StepExecution.put_runtime_view_output(view_output)

      ei = RuntimeArtifacts.require_introspect(model)

      runtime_view_tree =
        cond do
          StepExecution.concrete_runtime_view_tree?(derived_view_tree, ei) ->
            derived_view_tree

          true ->
            case RuntimeViewOutput.tree(model, target) do
              %{} = output_tree when map_size(output_tree) > 0 ->
                if StepExecution.concrete_runtime_view_tree?(output_tree, ei),
                  do: output_tree,
                  else: nil

              _ ->
                nil
            end
        end

      runtime_view_tree =
        if is_map(runtime_view_tree) do
          runtime_view_tree
        else
          preview_unavailable_view_tree(
            target,
            preview_error || "runtime view did not produce drawable output"
          )
        end

      surface_runtime
      |> Map.put(:model, model)
      |> put_debugger_view_tree(runtime_view_tree)
    else
      surface_runtime
    end
  end

  def render_view_from_surface(_surface_runtime, _target), do: nil

  @spec force_executor_view_preview?(
          Types.view_output_tree(),
          Types.execution_model(),
          Types.surface_target()
        ) :: boolean()
  defp force_executor_view_preview?(surface_view_tree, execution_model, :watch) do
    RuntimeArtifacts.versioned_elmx_artifacts?(execution_model) and
      (StepExecution.placeholder_view_tree?(surface_view_tree) or surface_view_tree == %{})
  end

  defp force_executor_view_preview?(_surface_view_tree, _execution_model, _target), do: false

  @doc """
  View-output rows for SVG preview: same executor refresh and resolution as rendered tree.
  """
  @spec effective_runtime_view_output_rows(
          Types.RuntimeStepResult.wire_result(),
          Types.app_model(),
          Types.surface_target()
        ) :: Types.runtime_view_nodes()
  def effective_runtime_view_output_rows(runtime, model, target)
      when is_map(runtime) and is_map(model) and target in [:watch, :companion, :phone] do
    stored_rows =
      Map.get(model, "runtime_view_output") || Map.get(model, :runtime_view_output) || []

    execution_model = RuntimeArtifacts.execution_model(runtime)
    view_tree = Map.get(runtime, :view_tree) || Map.get(runtime, "view_tree") || %{}

    preview_model =
      case Map.get(model, "runtime_model") || Map.get(model, :runtime_model) do
        %{} = runtime_model -> runtime_model
        _ -> model
      end

    {rows, view_tree} =
      case StepExecution.maybe_executor_view_preview(
             execution_model,
             model,
             target,
             stored_rows
           ) do
        {:ok, %{view_output: rows, view_tree: fresh_tree}} ->
          {rows, fresh_tree || view_tree}

        :skip ->
          {stored_rows, view_tree}
      end

    StepExecution.resolve_runtime_view_output(
      execution_model,
      view_tree,
      preview_model,
      rows
    )
  end

  @spec enrich_surface_resource_indices(Surface.surface_map(), Types.runtime_state()) ::
          Surface.surface_map()
  defp enrich_surface_resource_indices(surface, state)
       when is_map(surface) and is_map(state) do
    project_slug = Map.get(state, :project_slug) || Map.get(state, :scope_key)

    surface
    |> enrich_shell_resource_indices(
      project_slug,
      :bitmap_resource_indices,
      &RuntimeArtifacts.bitmap_resource_indices/1,
      &RuntimeArtifacts.bitmap_resource_indices_for_project/1
    )
    |> enrich_shell_resource_indices(
      project_slug,
      :vector_resource_indices,
      &RuntimeArtifacts.vector_resource_indices/1,
      &RuntimeArtifacts.vector_resource_indices_for_project/1
    )
    |> enrich_shell_resource_indices(
      project_slug,
      :animation_resource_indices,
      &RuntimeArtifacts.animation_resource_indices/1,
      &RuntimeArtifacts.animation_resource_indices_for_project/1
    )
  end

  defp enrich_surface_resource_indices(surface, _state), do: surface

  defp enrich_shell_resource_indices(surface, project_slug, key, get_fn, load_fn) do
    execution_model = RuntimeArtifacts.execution_model(surface)

    if map_size(get_fn.(execution_model)) > 0 do
      surface
    else
      indices =
        if is_binary(project_slug) do
          load_fn.(project_slug)
        else
          %{}
        end

      if map_size(indices) > 0 do
        Surface.put_shell(surface, Map.put(Surface.shell(surface), Atom.to_string(key), indices))
      else
        surface
      end
    end
  end

  @spec preview_from_surface_trees(
          Types.view_output_tree(),
          Types.inner_runtime_model(),
          Types.runtime_view_nodes(),
          Types.elm_introspect(),
          Types.execution_model(),
          Types.app_model(),
          Types.surface_target()
        ) :: Types.preview_view_derivation()
  defp preview_from_surface_trees(
         surface_view_tree,
         preview_model,
         stored_rows,
         ei,
         execution_model,
         model,
         target
       ) do
    cond do
      StepExecution.usable_runtime_view_tree?(
        surface_view_tree,
        preview_model,
        ei,
        execution_model
      ) ->
        %{
          view_tree: surface_view_tree,
          view_output:
            StepExecution.supplemental_view_output_rows(surface_view_tree, execution_model)
        }

      StepExecution.stale_runtime_view_output?(preview_model, stored_rows) ->
        case StepExecution.executor_view_preview(execution_model, model, target) do
          {:ok, fresh} ->
            fresh

          :error ->
            StepExecution.derive_preview_view_output(
              execution_model,
              surface_view_tree,
              preview_model
            )
        end

      true ->
        StepExecution.derive_preview_view_output(
          execution_model,
          surface_view_tree,
          preview_model
        )
    end
  end

  @spec preview_model_for_message(Types.app_model(), String.t() | nil) :: Types.app_model()
  defp preview_model_for_message(preview_model, _message) when is_map(preview_model),
    do: preview_model

  @spec put_debugger_view_tree(Surface.surface_map(), Types.view_output_tree() | nil) ::
          Surface.surface_map()
  def put_debugger_view_tree(runtime, runtime_view_tree) when is_map(runtime) do
    ei = RuntimeArtifacts.introspect(runtime) || %{}

    cond do
      preview_unavailable_tree?(runtime_view_tree) ->
        Map.put(runtime, :view_tree, runtime_view_tree)

      StepExecution.introspect_view_usable?(runtime_view_tree, ei) ->
        Map.put(runtime, :view_tree, runtime_view_tree)

      true ->
        runtime
    end
  end

  @spec preview_unavailable_tree?(Types.view_output_tree() | nil) :: boolean()
  defp preview_unavailable_tree?(%{"type" => "previewUnavailable"}), do: true
  defp preview_unavailable_tree?(%{type: "previewUnavailable"}), do: true
  defp preview_unavailable_tree?(_), do: false

  @spec supplement_without_executor(
          Types.runtime_state(),
          Types.surface_target(),
          Types.execution_model(),
          Types.elm_introspect()
        ) :: Types.runtime_state()
  def supplement_without_executor(state, target, execution_model, introspect)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(execution_model) and
             is_map(introspect) do
    surface = state |> Map.get(target, %{}) |> RuntimeArtifacts.normalize_surface()

    case render_view_from_surface(
           Map.put(surface, :model, get_in(state, [target, :model]) || %{}),
           target
         ) do
      %{} = runtime -> put_in(state, [target], runtime)
      _ -> state
    end
  end

  def supplement_without_executor(state, _target, _execution_model, _introspect), do: state

  @spec has_drawable_output?(Types.app_model()) :: boolean()
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

  @spec preview_unavailable_view_tree(Types.surface_target(), String.t()) ::
          Types.view_output_tree()
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
