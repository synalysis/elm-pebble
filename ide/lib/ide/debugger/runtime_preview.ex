defmodule Ide.Debugger.RuntimePreview do
  @moduledoc false

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
      parser_view_tree =
        StepExecution.introspect_parser_view_tree(
          execution_model,
          Map.get(surface, :view_tree) || %{}
        )

      preview_model =
        model
        |> RuntimeArtifacts.preview_runtime_model()
        |> preview_model_for_message(Map.get(model, "runtime_last_message"))

      preview =
        StepExecution.derive_preview_view_output(execution_model, parser_view_tree, preview_model)

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

  @spec enrich_surface_resource_indices(Surface.surface_map(), Types.runtime_state()) ::
          Surface.surface_map()
  defp enrich_surface_resource_indices(surface, state)
       when is_map(surface) and is_map(state) do
    execution_model = RuntimeArtifacts.execution_model(surface)

    if map_size(RuntimeArtifacts.bitmap_resource_indices(execution_model)) > 0 do
      surface
    else
      project_slug = Map.get(state, :project_slug) || Map.get(state, :scope_key)

      indices =
        if is_binary(project_slug) do
          RuntimeArtifacts.bitmap_resource_indices_for_project(project_slug)
        else
          %{}
        end

      if map_size(indices) > 0 do
        Surface.put_shell(surface, Map.put(Surface.shell(surface), "bitmap_resource_indices", indices))
      else
        surface
      end
    end
  end

  defp enrich_surface_resource_indices(surface, _state), do: surface

  @spec preview_model_for_message(Types.app_model(), String.t() | nil) :: Types.app_model()
  defp preview_model_for_message(preview_model, _message) when is_map(preview_model), do: preview_model

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

  @spec preview_unavailable_view_tree(Types.surface_target(), String.t()) :: Types.view_output_tree()
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
