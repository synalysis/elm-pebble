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

  @spec runtime_result(StepInput.t(), [String.t()]) :: Types.runtime_step_result()
  def runtime_result(%StepInput{} = step, update_branches)
       when is_binary(step.message) do
    request =
      step
      |> StepExecutionContract.request_from(update_branches: update_branches)
      |> Ide.Debugger.RuntimeExecutor.Request.to_map()

    case executor_module().execute(request) do
      {:ok, %{model_patch: patch} = result} when is_map(patch) ->
        if is_map(Map.get(patch, "runtime_model")) do
          result
          |> Map.put(
            :view_output,
            normalize_view_output(
              Map.get(result, :view_output) || Map.get(patch, "runtime_view_output")
            )
          )
          |> Map.put(:protocol_events, normalize_protocol_events(Map.get(result, :protocol_events)))
          |> Map.put(:followup_messages, normalize_followup_messages(Map.get(result, :followup_messages)))
          |> StepExecutionContract.step_result_from_executor()
        else
          local_runtime_result(step.execution_model, step.view_tree, step.message, update_branches)
        end

      _ ->
        local_runtime_result(step.execution_model, step.view_tree, step.message, update_branches)
    end
  end

  @spec local_runtime_result(
          Types.execution_model(),
          map(),
          String.t(),
          [String.t()]
        ) :: Types.runtime_step_result()
  def local_runtime_result(model, view_tree, message, update_branches) do
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    updated_runtime_model = mutate_runtime_model(runtime_model, message, update_branches)

    StepExecutionContract.step_result_from_local_fallback(
      model
      |> Map.put("runtime_model", updated_runtime_model)
      |> refresh_runtime_fingerprints(updated_runtime_model, view_tree)
      |> Map.take([
        "runtime_model",
        "runtime_model_source",
        "runtime_model_sha256",
        "runtime_view_tree_sha256",
        "elm_executor_mode",
        "elm_executor"
      ]),
      view_tree
    )
  end

  @spec normalize_protocol_events(list()) :: [map()]
  def normalize_protocol_events(value) when is_list(value), do: value
  def normalize_protocol_events(_), do: []

  @spec normalize_followup_messages(list()) :: [String.t()]
  def normalize_followup_messages(value) when is_list(value), do: value
  def normalize_followup_messages(_), do: []

  @spec normalize_view_output(list()) :: [map()]
  def normalize_view_output(value) when is_list(value), do: value
  def normalize_view_output(_), do: []

  @spec put_runtime_view_output(map(), list()) :: map()
  def put_runtime_view_output(model, view_output) when is_map(model) do
    case normalize_view_output(view_output) do
      [] -> model
      rows -> Map.put(model, "runtime_view_output", rows)
    end
  end
  @spec preferred_view_output(list(), list()) :: [map()]
  def preferred_view_output(primary, fallback) do
    choose_runtime_view_output(primary, fallback)
  end

  @spec choose_runtime_view_output(list(), list()) :: [map()]
  def choose_runtime_view_output(primary, supplemental) do
    primary_rows = normalize_view_output(primary)
    supplemental_rows = normalize_view_output(supplemental)

    primary_vector_ids = vector_at_ids(primary_rows)
    supplemental_vector_ids = vector_at_ids(supplemental_rows)

    prefer_supplemental_vectors? =
      supplemental_vector_ids != [] and
        (primary_vector_ids == [] or primary_vector_ids != supplemental_vector_ids)

    cond do
      supplemental_rows == [] ->
        primary_rows

      primary_rows == [] ->
        supplemental_rows

      prefer_supplemental_vectors? ->
        supplemental_rows

      resolved_vector_rows?(supplemental_rows) and not resolved_vector_rows?(primary_rows) ->
        supplemental_rows

      vector_rows?(supplemental_rows) and not vector_rows?(primary_rows) ->
        supplemental_rows

      parser_preview_resolved?(supplemental_rows) and parser_preview_unresolved?(primary_rows) ->
        supplemental_rows

      length(supplemental_rows) > length(primary_rows) ->
        supplemental_rows

      true ->
        primary_rows
    end
  end

  def vector_rows?(rows) when is_list(rows),
    do: Enum.any?(rows, &(is_map(&1) and Map.get(&1, "kind") == "vector_at"))

  def vector_at_ids(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn
      %{"kind" => "vector_at", "vector_id" => id} when is_integer(id) -> [id]
      %{kind: "vector_at", vector_id: id} when is_integer(id) -> [id]
      _ -> []
    end)
  end

  def resolved_vector_rows?(rows) when is_list(rows) do
    Enum.any?(rows, fn row ->
      is_map(row) and Map.get(row, "kind") == "vector_at" and is_integer(Map.get(row, "vector_id"))
    end)
  end

  def parser_preview_unresolved?(rows) when is_list(rows),
    do: Enum.any?(rows, &(is_map(&1) and Map.get(&1, "kind") == "unresolved"))

  def parser_preview_resolved?(rows) when is_list(rows),
    do: rows != [] and not parser_preview_unresolved?(rows)

  @spec supplement_parser_runtime_view_output(Types.execution_model(), map(), map()) :: [map()]
  def supplement_parser_runtime_view_output(execution_model, view_tree, runtime_model)
       when is_map(execution_model) and is_map(view_tree) and is_map(runtime_model) do
    view_tree = introspect_parser_view_tree(execution_model, view_tree)

    if map_size(view_tree) == 0 do
      []
    else
      eval_context =
        execution_model
        |> RuntimeArtifacts.core_ir_eval_context()
        |> then(fn base ->
          case RuntimeArtifacts.introspect(execution_model) do
            %{} = ei -> Map.put(base, :elm_introspect, ei)
            _ -> base
          end
        end)

      preview_model =
        runtime_model
        |> Map.merge(screen_dimensions_for_view_preview(execution_model))

      ElmExecutor.Runtime.SemanticExecutor.derive_view_output_preview(
        view_tree,
        preview_model,
        eval_context
      )
    end
  end

  @spec introspect_parser_view_tree(Types.execution_model(), map()) :: map()
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

  @spec screen_dimensions_for_view_preview(map()) :: map()
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

  @spec render_view_after_update(
          map() | nil,
          map() | nil,
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          keyword()
        ) :: map()
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
    output_view_tree = RuntimeViewOutput.tree(model, target)
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

  @spec normalize_debugger_render_tree(map()) :: map()
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

  @spec concrete_runtime_view_tree?(map(), map()) :: boolean()
  def concrete_runtime_view_tree?(%{"type" => _} = tree, ei) when is_map(ei) do
    introspect_view_usable?(tree, ei) and not parser_expression_view_tree?(tree, ei)
  end

  def concrete_runtime_view_tree?(_tree, _ei), do: false

  @spec parser_expression_view_tree?(map(), map()) :: boolean()
  def parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  def parser_expression_view_tree?(_tree, _ei), do: false
  @spec introspect_view_usable?(map(), Types.elm_introspect()) :: boolean()
  def introspect_view_usable?(%{"type" => "unknown", "children" => []}, _ei), do: false

  def introspect_view_usable?(%{"type" => type} = tree, ei) when is_binary(type) do
    type not in ["root", "unknown", "previewUnavailable"] and
      not unresolved_parser_view_root?(tree, ei)
  end

  def introspect_view_usable?(%{"children" => children}, _ei)
       when is_list(children) and children != [],
       do: true

  def introspect_view_usable?(_tree, _ei), do: false

  @spec unresolved_parser_view_root?(map(), Types.elm_introspect()) :: boolean()
  def unresolved_parser_view_root?(tree, ei) when is_map(tree) and is_map(ei),
    do: Ide.Debugger.ElmIntrospect.parser_expression_view_tree_node?(tree, ei)

  def unresolved_parser_view_root?(_tree, _ei), do: false

  @spec mutate_runtime_model(map(), String.t(), [String.t()]) :: map()
  def mutate_runtime_model(model, message, update_branches)
       when is_map(model) and is_binary(message) and is_list(update_branches) do
    op = step_operation_for_message(message, update_branches)

    {updated, changed?} =
      Enum.reduce(model, {%{}, false}, fn {key, value}, {acc, changed?} ->
        cond do
          is_integer(value) and op == :inc ->
            {Map.put(acc, key, value + 1), true}

          is_integer(value) and op == :dec ->
            {Map.put(acc, key, value - 1), true}

          is_integer(value) and op == :reset ->
            {Map.put(acc, key, 0), true}

          is_boolean(value) and op == :toggle ->
            {Map.put(acc, key, !value), true}

          is_boolean(value) and op == :enable ->
            {Map.put(acc, key, true), true}

          is_boolean(value) and op == :disable ->
            {Map.put(acc, key, false), true}

          is_boolean(value) and op == :reset ->
            {Map.put(acc, key, false), true}

          true ->
            {Map.put(acc, key, value), changed?}
        end
      end)

    base =
      if changed? do
        updated
      else
        Map.put(model, "step_counter", Map.get(model, "step_counter", 0) + 1)
      end

    base
    |> Map.put("last_message", message)
    |> Map.put("last_operation", Atom.to_string(op))
  end
  @spec step_operation_for_message(String.t(), [String.t()]) :: atom()
  def step_operation_for_message(message, update_branches)
       when is_binary(message) and is_list(update_branches) do
    case operation_from_text(message) do
      :tick ->
        update_branches
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&operation_from_text/1)
        |> Enum.find(:tick, &(&1 != :tick))

      op ->
        op
    end
  end

  @spec contains_any?(String.t(), [String.t()] | String.t()) :: boolean()
  def contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, fn needle -> String.contains?(text, needle) end)
  end

  @spec operation_from_text(String.t()) :: atom()
  def operation_from_text(text) when is_binary(text) do
    hint = String.downcase(text)

    cond do
      contains_any?(hint, ["inc", "increment", "up", "next", "plus", "add"]) -> :inc
      contains_any?(hint, ["dec", "decrement", "down", "prev", "minus", "sub"]) -> :dec
      contains_any?(hint, ["toggle", "flip", "switch"]) -> :toggle
      contains_any?(hint, ["enable", "enabled", "on", "open", "start"]) -> :enable
      contains_any?(hint, ["disable", "disabled", "off", "close", "stop"]) -> :disable
      contains_any?(hint, ["reset", "clear"]) -> :reset
      true -> :tick
    end
  end
  @spec refresh_runtime_fingerprints(Types.execution_model(), map(), map()) :: Types.execution_model()
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

  @spec maybe_put_runtime_source(map(), String.t(), String.t() | nil) :: map()
  def maybe_put_runtime_source(runtime, _key, value) when not is_binary(value), do: runtime
  def maybe_put_runtime_source(runtime, _key, value) when value == "", do: runtime
  def maybe_put_runtime_source(runtime, key, value), do: Map.put(runtime, key, value)
  @spec view_tree_node_count(map() | [map()]) :: non_neg_integer()
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

  @spec stable_term_sha256(map() | list()) :: String.t()
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

  @spec preview_unavailable_view_tree(Types.surface_target(), String.t()) :: map()
  defp preview_unavailable_view_tree(target, reason) do
    %{
      "type" => "previewUnavailable",
      "label" => reason,
      "target" => source_root_for_target(target),
      "children" => []
    }
  end
end
