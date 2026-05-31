defmodule Ide.Debugger.StepExecution do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.StepExecutionContract

  @type resolve_result :: {
          String.t(),
          String.t(),
          [String.t()],
          [String.t()],
          non_neg_integer()
        }

  @spec resolve_message(Types.execution_model(), String.t() | nil) ::
          {String.t(), String.t(), [String.t()], [String.t()], non_neg_integer()}
  def resolve_message(model, requested_message) when is_map(model) do
    ei = RuntimeArtifacts.require_introspect(model)
    msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
    update_branches = IntrospectAccess.list(ei, "update_case_branches")

    known_messages =
      if msg_constructors != [] do
        msg_constructors
      else
        update_branches
      end

    cursor = integer_or_zero(Map.get(model, "runtime_message_cursor"))

    cond do
      is_binary(requested_message) and String.trim(requested_message) != "" ->
        message = canonicalize_known_message(String.trim(requested_message), known_messages)
        {message, "provided", known_messages, update_branches, cursor + 1}

      known_messages != [] ->
        idx = rem(cursor, length(known_messages))
        message = Enum.at(known_messages, idx) || "Tick"
        {message, "auto_cycle", known_messages, update_branches, cursor + 1}

      true ->
        {"Tick", "default", [], update_branches, cursor + 1}
    end
  end

  @spec canonicalize_known_message(String.t(), [String.t()]) :: String.t()
  def canonicalize_known_message(message, known_messages) when is_binary(message) do
    trimmed = String.trim(message)

    case String.split(trimmed, ~r/\s+/, parts: 2) do
      [constructor, payload] when is_binary(payload) and payload != "" ->
        canonical_constructor = canonicalize_message_constructor(constructor, known_messages)
        "#{canonical_constructor} #{payload}"

      _ ->
        needle = String.downcase(trimmed)

        Enum.find(known_messages, trimmed, fn known ->
          if is_binary(known) do
            known_down = String.downcase(known)

            known_down == needle or
              String.starts_with?(needle, known_down <> " ") or
              String.starts_with?(needle, known_down <> "(")
          else
            false
          end
        end)
    end
  end

  @spec canonicalize_message_constructor(String.t(), [String.t()]) :: String.t()
  def canonicalize_message_constructor(constructor, known_messages) when is_binary(constructor) do
    ctor_down = String.downcase(constructor)

    Enum.find_value(known_messages, constructor, fn known ->
      if is_binary(known) do
        known_ctor =
          known
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()

        if is_binary(known_ctor) and String.downcase(known_ctor) == ctor_down do
          known_ctor
        end
      end
    end)
  end

  @spec runtime_result(StepInput.t(), [String.t()]) ::
          {:ok, Types.runtime_step_result()} | {:error, Types.execution_error()}
  def runtime_result(%StepInput{} = step, update_branches)
       when is_binary(step.message) do
    request =
      step
      |> StepExecutionContract.request_from(update_branches: update_branches)
      |> Ide.Debugger.RuntimeExecutor.Request.to_map()

    case executor_module().execute(request) do
      {:ok, %{model_patch: patch} = result} when is_map(patch) ->
        if is_map(Map.get(patch, "runtime_model")) do
          {:ok,
           result
           |> Map.put(
             :view_output,
             normalize_view_output(
               Map.get(result, :view_output) || Map.get(patch, "runtime_view_output")
             )
           )
           |> Map.put(:protocol_events, normalize_protocol_events(Map.get(result, :protocol_events)))
           |> Map.put(:followup_messages, normalize_followup_messages(Map.get(result, :followup_messages)))
           |> StepExecutionContract.step_result_from_executor()}
        else
          {:error, {:core_ir_execution_failed, :missing_runtime_model}}
        end

      {:error, _} = err ->
        err

      _ ->
        {:error, {:core_ir_execution_failed, :invalid_executor_result}}
    end
  end

  @spec normalize_protocol_events(list()) :: [Types.protocol_timeline_event()]
  def normalize_protocol_events(value) when is_list(value), do: value
  def normalize_protocol_events(_), do: []

  @spec normalize_followup_messages(list()) :: [String.t()]
  def normalize_followup_messages(value) when is_list(value), do: value
  def normalize_followup_messages(_), do: []

  @spec normalize_view_output(list()) :: Types.runtime_view_nodes()
  def normalize_view_output(value) when is_list(value), do: value
  def normalize_view_output(_), do: []

  @spec put_runtime_view_output(Types.app_model(), Types.runtime_view_nodes()) :: Types.app_model()
  def put_runtime_view_output(model, view_output) when is_map(model) do
    case normalize_view_output(view_output) do
      [] -> model
      rows -> Map.put(model, "runtime_view_output", rows)
    end
  end
  @spec preferred_view_output(Types.runtime_view_nodes(), Types.runtime_view_nodes()) ::
          Types.runtime_view_nodes()
  def preferred_view_output(primary, fallback) do
    choose_runtime_view_output(primary, fallback)
  end

  @spec resolve_runtime_view_output(
          Types.execution_model(),
          Types.view_output_tree(),
          Types.app_model(),
          Types.runtime_view_nodes()
        ) :: Types.runtime_view_nodes()
  def resolve_runtime_view_output(execution_model, view_tree, model_for_view, executor_rows)
      when is_map(execution_model) and is_map(view_tree) and is_map(model_for_view) do
    case normalize_view_output(executor_rows) do
      [] ->
        derive_preview_view_output(
          execution_model,
          view_tree,
          RuntimeArtifacts.preview_runtime_model(model_for_view)
        )
        |> Map.get(:view_output, [])

      rows ->
        rows
    end
  end

  @spec choose_runtime_view_output(Types.runtime_view_nodes(), Types.runtime_view_nodes()) ::
          Types.runtime_view_nodes()
  def choose_runtime_view_output(primary, _supplemental) do
    normalize_view_output(primary)
  end

  @spec derive_preview_view_output(
          Types.execution_model(),
          Types.view_output_tree(),
          Types.inner_runtime_model()
        ) :: Types.preview_view_derivation()
  def derive_preview_view_output(execution_model, view_tree, preview_model)
      when is_map(execution_model) and is_map(view_tree) and is_map(preview_model) do
    eval_context = preview_eval_context(execution_model)

    preview_model =
      preview_model
      |> RuntimeArtifacts.preview_runtime_model()
      |> Map.merge(screen_dimensions_for_view_preview(execution_model))

    case RuntimeArtifacts.versioned_core_ir?(execution_model) do
      true ->
        %{view_output: rows, view_tree: tree} =
          ElmExecutor.Runtime.SemanticExecutor.derive_view_output_for_runtime_model(
            preview_model,
            eval_context
          )

        %{view_output: normalize_view_output(rows), view_tree: tree}

      false ->
        %{view_output: [], view_tree: nil, preview_error: "missing_core_ir"}
    end
  end

  @spec preview_eval_context(Types.execution_model()) :: Types.core_ir_eval_context()
  defp preview_eval_context(execution_model) when is_map(execution_model) do
    execution_model
    |> RuntimeArtifacts.core_ir_eval_context()
    |> then(fn base ->
      case RuntimeArtifacts.introspect(execution_model) do
        %{} = ei -> Map.put(base, :elm_introspect, ei)
        _ -> base
      end
    end)
  end

  @spec introspect_parser_view_tree(Types.execution_model(), Types.view_output_tree()) ::
          Types.view_output_tree()
  def introspect_parser_view_tree(execution_model, view_tree) when is_map(execution_model) do
    case introspect_view_tree(RuntimeArtifacts.introspect(execution_model)) do
      %{} = tree ->
        tree

      _ ->
        case view_tree do
          %{"type" => type} = tree when is_binary(type) and type not in ["root", "unknown", "previewUnavailable"] ->
            tree

          _ ->
            %{}
        end
    end
  end

  def introspect_view_tree(%{} = introspect), do: Map.get(introspect, "view_tree") || %{}
  def introspect_view_tree(_), do: %{}

  @spec screen_dimensions_for_view_preview(Types.execution_model()) :: Types.screen_dimension_patch()
  def screen_dimensions_for_view_preview(execution_model) when is_map(execution_model) do
    %{
      "screenW" =>
        Map.get(execution_model, "screen_width") ||
          Map.get(execution_model, "screenW") ||
          get_in(execution_model, ["launch_context", "screen", "width"]),
      "screenH" =>
        Map.get(execution_model, "screen_height") ||
          Map.get(execution_model, "screenH") ||
          get_in(execution_model, ["launch_context", "screen", "height"])
    }
    |> Enum.reject(fn {_key, value} -> not is_integer(value) end)
    |> Map.new()
  end

  @spec runtime_view_output_tree(
          Types.app_model(),
          Types.surface_target(),
          Types.view_output_tree() | nil,
          keyword()
        ) :: Types.view_output_tree() | nil
  def runtime_view_output_tree(model, target, runtime_view_tree, opts)
      when is_map(model) and target in [:watch, :companion, :phone] and is_list(opts) do
    case RuntimeViewOutput.tree(model, target) do
      %{} = tree ->
        tree

      nil ->
        case Keyword.get(opts, :execution_model) do
          %{} = execution_model ->
            derive_preview_view_output(
              execution_model,
              runtime_view_tree || %{},
              RuntimeArtifacts.preview_runtime_model(model)
            )
            |> Map.get(:view_output, [])
            |> case do
              [] ->
                nil

              rows ->
                RuntimeViewOutput.tree(Map.put(model, "runtime_view_output", rows), target)
            end

          _ ->
            nil
        end
    end
  end

  @spec render_view_after_update(
          Types.view_output_tree() | nil,
          Types.view_output_tree() | nil,
          Types.surface_target(),
          String.t(),
          String.t(),
          Types.app_model(),
          keyword()
        ) :: Types.view_output_tree()
  def render_view_after_update(
         runtime_view_tree,
         previous_view_tree,
         target,
         message,
         trigger,
         model,
         opts
       )

  def render_view_after_update(
         runtime_view_tree,
         previous_view_tree,
         target,
         message,
         trigger,
         model,
         opts
       )
       when target in [:watch, :companion, :phone] and is_binary(message) and is_binary(trigger) and
              is_map(model) and is_list(opts) do
    output_view_tree = runtime_view_output_tree(model, target, runtime_view_tree, opts)
    ei = RuntimeArtifacts.require_introspect(model)

    base =
      cond do
        is_map(output_view_tree) ->
          output_view_tree

        concrete_runtime_view_tree?(runtime_view_tree, ei) ->
          runtime_view_tree

        parser_expression_view_tree?(runtime_view_tree, ei) ->
          preview_unavailable_view_tree(target, "runtime view did not produce drawable output")

        concrete_runtime_view_tree?(previous_view_tree, ei) ->
          previous_view_tree

        true ->
          preview_unavailable_view_tree(target, "no renderable view tree")
      end

    base = normalize_debugger_render_tree(base)

    children =
      case Map.get(base, "children") || Map.get(base, :children) do
        xs when is_list(xs) -> xs
        _ -> []
      end

    render_marker = %{
      "type" => "debuggerRenderStep",
      "label" => "#{source_root_for_target(target)}:#{message}",
      "trigger" => trigger,
      "model_entries" => map_size(model),
      "children" => []
    }

    base
    |> Map.put("children", [render_marker | children] |> Enum.take(24))
    |> Map.put("last_runtime_step_message", message)
    |> Map.put("last_runtime_trigger", trigger)
  end

  def render_view_after_update(
         _runtime_view_tree,
         previous_view_tree,
         target,
         _message,
         _trigger,
         _model,
         opts
       )
       when target in [:watch, :companion, :phone] and is_list(opts) do
    default_view_tree = Keyword.get(opts, :default_view_tree, %{})

    if is_map(previous_view_tree) and map_size(previous_view_tree) > 0,
      do: previous_view_tree,
      else: default_view_tree
  end

  @spec normalize_debugger_render_tree(Types.view_output_tree()) :: Types.view_output_tree()
  def normalize_debugger_render_tree(%{"type" => "Window"} = tree) do
    window =
      tree
      |> Map.put("type", "window")
      |> Map.put_new("label", "")

    %{"type" => "windowStack", "label" => "", "children" => [window]}
  end

  def normalize_debugger_render_tree(%{"type" => "WindowStack"} = tree) do
    tree
    |> Map.put("type", "windowStack")
    |> Map.put_new("label", "")
  end

  def normalize_debugger_render_tree(tree), do: tree

  @spec concrete_runtime_view_tree?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def concrete_runtime_view_tree?(%{"type" => _} = tree, ei) when is_map(ei) do
    introspect_view_usable?(tree, ei) and not parser_expression_view_tree?(tree, ei)
  end

  def concrete_runtime_view_tree?(_tree, _ei), do: false

  @spec parser_expression_view_tree?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  def parser_expression_view_tree?(_tree, _ei), do: false
  @spec introspect_view_usable?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def introspect_view_usable?(%{"type" => "unknown", "children" => []}, _ei), do: false

  def introspect_view_usable?(%{"type" => type} = tree, ei) when is_binary(type) do
    type not in ["root", "unknown", "previewUnavailable"] and
      not unresolved_parser_view_root?(tree, ei)
  end

  def introspect_view_usable?(%{"children" => children}, _ei)
       when is_list(children) and children != [],
       do: true

  def introspect_view_usable?(_tree, _ei), do: false

  @spec unresolved_parser_view_root?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def unresolved_parser_view_root?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  def unresolved_parser_view_root?(_tree, _ei), do: false

  @spec refresh_runtime_fingerprints(
          Types.execution_model(),
          Types.app_model(),
          Types.view_output_tree()
        ) :: Types.execution_model()
  def refresh_runtime_fingerprints(model, runtime_model, view_tree)
       when is_map(model) and is_map(runtime_model) do
    runtime = Map.get(model, "elm_executor")
    runtime_mode = Map.get(model, "elm_executor_mode")
    runtime_model_source = Map.get(model, "runtime_model_source")
    runtime_view_tree_source = Map.get(model, "runtime_view_tree_source")

    if runtime_mode == "runtime_executed" or (is_map(runtime) and map_size(runtime) > 0) or
         map_size(runtime_model) > 0 do
      runtime = if is_map(runtime), do: runtime, else: %{}
      runtime_view_tree = if is_map(view_tree), do: view_tree, else: %{}

      runtime =
        runtime
        |> Map.put("runtime_model_entry_count", map_size(runtime_model))
        |> Map.put("view_tree_node_count", view_tree_node_count(runtime_view_tree))
        |> Map.put("runtime_model_sha256", stable_term_sha256(runtime_model))
        |> Map.put("view_tree_sha256", stable_term_sha256(runtime_view_tree))
        |> maybe_put_runtime_source("runtime_model_source", runtime_model_source)
        |> maybe_put_runtime_source("view_tree_source", runtime_view_tree_source)

      model
      |> Map.put("elm_executor", runtime)
      |> Map.put("runtime_model_sha256", runtime["runtime_model_sha256"])
      |> Map.put("runtime_view_tree_sha256", runtime["view_tree_sha256"])
    else
      model
    end
  end

  @spec maybe_put_runtime_source(Types.view_output_tree(), String.t(), String.t() | nil) ::
          Types.view_output_tree()
  def maybe_put_runtime_source(runtime, _key, value) when not is_binary(value), do: runtime
  def maybe_put_runtime_source(runtime, _key, value) when value == "", do: runtime
  def maybe_put_runtime_source(runtime, key, value), do: Map.put(runtime, key, value)
  @spec view_tree_node_count(Types.view_output_tree() | [Types.view_output_tree()]) :: non_neg_integer()
  def view_tree_node_count(%{"children" => children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  def view_tree_node_count(%{children: children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  def view_tree_node_count(%{}), do: 1
  def view_tree_node_count(_), do: 0

  @spec stable_term_sha256(Types.normalized_export_term() | list()) :: String.t()
  def stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec executor_module() :: module()
  defp executor_module do
    Application.get_env(:ide, Ide.Debugger, [])
    |> Keyword.get(:runtime_executor_module, RuntimeExecutor)
  end

  @spec source_root_for_target(Types.surface_target()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"

  @spec integer_or_zero(Types.wire_input()) :: non_neg_integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0

  @spec preview_unavailable_view_tree(Types.surface_target(), String.t()) :: Types.view_output_tree()
  defp preview_unavailable_view_tree(target, reason) do
    %{
      "type" => "previewUnavailable",
      "label" => reason,
      "target" => source_root_for_target(target),
      "children" => []
    }
  end
end
