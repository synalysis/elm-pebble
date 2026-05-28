defmodule Ide.Debugger.RuntimeExecutor do
  @moduledoc """
  Deterministic runtime execution seam for debugger reloads.

  The current executor derives a stable runtime snapshot from parser introspection data,
  and provides a single place to swap in a fuller interpreter-backed engine.
  """

  alias Ide.Debugger.RuntimeExecutor.Request
  alias Ide.Debugger.RuntimeExecutor.ResultNormalizer
  alias Ide.Debugger.RuntimeExecutor.Types, as: ExecutorTypes
  alias Ide.Debugger.RuntimeExecutor.Types.RuntimeMode
  alias Ide.Debugger.Types

  @type execution_input :: ExecutorTypes.execution_input()
  @type execution_result :: ExecutorTypes.execution_result()
  @type execute_request :: execution_input()

  @type fallback_reason :: Types.execution_fallback_reason()

  @callback execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}

  @spec execute(execution_input()) :: {:ok, execution_result()} | {:error, Types.execution_error()}
  def execute(%Request{} = input), do: execute(Request.to_map(input))

  def execute(input) when is_map(input) do
    case runtime_mode() do
      :legacy ->
        execute_default_with_backend(input, "legacy_default")

      :hybrid ->
        case maybe_execute_external(input) do
          {:ok, payload} -> {:ok, annotate_execution_backend(payload, "external")}
          {:error, _reason} = err -> err
          {:fallback, reason} -> execute_default_with_backend(input, "fallback_default", reason)
          :no_external -> execute_default_with_backend(input, "default")
        end

      :runtime_first ->
        case maybe_execute_external(input) do
          {:ok, payload} -> {:ok, annotate_execution_backend(payload, "external")}
          {:error, _reason} = err -> err
          {:fallback, reason} -> execute_default_with_backend(input, "fallback_default", reason)
          :no_external -> execute_default_with_backend(input, "default")
        end
    end
  end

  def execute(_),
    do:
      {:ok,
       %{
         model_patch: %{},
         view_tree: nil,
         view_output: [],
         runtime: %{},
         protocol_events: [],
         followup_messages: []
       }}

  @doc false
  @spec execute_introspect_only(execution_input()) :: {:ok, execution_result()}
  def execute_introspect_only(input) when is_map(input) do
    execute_default_with_backend(input, "parser_only")
  end

  @spec execute_default_with_backend(execution_input(), String.t(), fallback_reason() | nil) ::
          {:ok, execution_result()}
  defp execute_default_with_backend(input, backend, reason \\ nil) do
    case execute_default(input) do
      {:ok, payload} -> {:ok, annotate_execution_backend(payload, backend, reason)}
    end
  end

  @spec execute_default(execution_input()) :: {:ok, execution_result()}
  defp execute_default(%{
         source_root: source_root,
         rel_path: rel_path,
         source: source,
         introspect: introspect,
         current_model: current_model,
         current_view_tree: current_view_tree,
         message: message,
         update_branches: update_branches
       })
       when is_map(introspect) and is_map(current_model) and is_binary(message) do
    runtime_model =
      case Map.get(current_model, "runtime_model") do
        value when is_map(value) -> value
        _ -> %{}
      end

    normalized_update_branches = normalize_update_branches(update_branches)
    op = step_operation_for_message(message, normalized_update_branches)

    updated_runtime_model =
      mutate_runtime_model(runtime_model, message, normalized_update_branches)

    runtime_view_tree =
      derive_step_view_tree(current_view_tree, updated_runtime_model, message, op, source_root)

    runtime = %{
      "engine" => "elm_introspect_runtime_v1",
      "source_root" => source_root,
      "rel_path" => rel_path,
      "source_byte_size" => byte_size(source),
      "msg_constructor_count" => list_count(Map.get(introspect, "msg_constructors")),
      "update_case_branch_count" => list_count(Map.get(introspect, "update_case_branches")),
      "view_case_branch_count" => list_count(Map.get(introspect, "view_case_branches")),
      "runtime_model_source" => "step_message",
      "view_tree_source" =>
        if(map_size(runtime_view_tree) > 0, do: "step_derived_view_tree", else: "none"),
      "runtime_model_entry_count" => map_size(updated_runtime_model),
      "view_tree_node_count" => view_tree_node_count(runtime_view_tree),
      "runtime_model_sha256" => stable_term_sha256(updated_runtime_model),
      "view_tree_sha256" => stable_term_sha256(runtime_view_tree)
    }

    {:ok,
     %{
       model_patch: %{
         "runtime_model" => updated_runtime_model,
         "runtime_model_source" => "step_message",
         "runtime_model_sha256" => runtime["runtime_model_sha256"],
         "runtime_view_tree_sha256" => runtime["view_tree_sha256"],
         "elm_executor_mode" => "runtime_executed",
         "elm_executor" => runtime
       },
       view_tree: if(map_size(runtime_view_tree) > 0, do: runtime_view_tree, else: nil),
       view_output: [],
       runtime: runtime,
       protocol_events: [],
       followup_messages: []
     }}
  end

  @spec execute_default(execution_input()) :: {:ok, execution_result()}
  defp execute_default(%{
         source_root: source_root,
         rel_path: rel_path,
         source: source,
         introspect: introspect
       })
       when is_map(introspect) do
    {init_model, runtime_model_source} =
      case Map.get(introspect, "init_model") do
        model when is_map(model) -> {model, "init_model"}
        _ -> {%{}, "none"}
      end

    {view_tree, view_tree_source} =
      case Map.get(introspect, "view_tree") do
        tree when is_map(tree) -> {tree, "parser_view_tree"}
        _ -> {nil, "none"}
      end

    runtime_view_tree = if is_map(view_tree), do: view_tree, else: %{}

    runtime = %{
      "engine" => "elm_introspect_runtime_v1",
      "source_root" => source_root,
      "rel_path" => rel_path,
      "source_byte_size" => byte_size(source),
      "msg_constructor_count" => list_count(Map.get(introspect, "msg_constructors")),
      "update_case_branch_count" => list_count(Map.get(introspect, "update_case_branches")),
      "view_case_branch_count" => list_count(Map.get(introspect, "view_case_branches")),
      "runtime_model_source" => runtime_model_source,
      "view_tree_source" => view_tree_source,
      "runtime_model_entry_count" => map_size(init_model),
      "view_tree_node_count" => view_tree_node_count(runtime_view_tree),
      "runtime_model_sha256" => stable_term_sha256(init_model),
      "view_tree_sha256" => stable_term_sha256(runtime_view_tree)
    }

    {:ok,
     %{
       model_patch: %{
         "runtime_model" => init_model,
         "runtime_model_source" => runtime_model_source,
         "runtime_model_sha256" => runtime["runtime_model_sha256"],
         "runtime_view_tree_sha256" => runtime["view_tree_sha256"],
         "elm_executor_mode" => "runtime_executed",
         "elm_executor" => runtime
       },
       view_tree: view_tree,
       view_output: [],
       runtime: runtime,
       protocol_events: [],
       followup_messages: []
     }}
  end

  defp execute_default(_),
    do:
      {:ok,
       %{
         model_patch: %{},
         view_tree: nil,
         view_output: [],
         runtime: %{},
         protocol_events: [],
         followup_messages: []
       }}

  @spec maybe_execute_external(execution_input()) ::
          {:ok, execution_result()} | {:error, Types.execution_error()} | {:fallback, fallback_reason()} | :no_external
  defp maybe_execute_external(input) when is_map(input) do
    module = external_executor_module()

    cond do
      not is_atom(module) ->
        :no_external

      not module_supports_execute?(module) ->
        :no_external

      true ->
        case module.execute(input) do
          {:ok, payload} when is_map(payload) ->
            {:ok, normalize_execution_result(payload)}

          {:ok, _invalid_payload} ->
            maybe_external_error_or_fallback({:invalid_external_runtime_result, :payload_not_map})

          {:error, reason} ->
            maybe_external_error_or_fallback({:external_runtime_executor_failed, reason})

          other ->
            maybe_external_error_or_fallback({:invalid_external_runtime_result, other})
        end
    end
  end

  @spec module_supports_execute?(module()) :: boolean()
  defp module_supports_execute?(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} -> function_exported?(module, :execute, 1)
      _ -> false
    end
  end

  @spec normalize_execution_result(ExecutorTypes.executor_wire_result() | map()) ::
          execution_result()
  defp normalize_execution_result(result) when is_map(result) do
    ResultNormalizer.normalize(result)
  end

  @spec maybe_external_error_or_fallback(fallback_reason()) ::
          {:error, fallback_reason()} | {:fallback, fallback_reason()}
  defp maybe_external_error_or_fallback(reason) do
    if external_executor_strict?() do
      {:error, reason}
    else
      {:fallback, reason}
    end
  end

  @spec annotate_execution_backend(execution_result(), String.t(), fallback_reason() | nil) ::
          execution_result()
  defp annotate_execution_backend(payload, backend, reason \\ nil)
       when is_map(payload) and is_binary(backend) do
    ResultNormalizer.annotate_backend(payload, backend, reason)
  end

  @spec external_executor_module() :: module() | nil
  defp external_executor_module do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:external_executor_module, Ide.Debugger.RuntimeExecutor.ElmExecutorAdapter)
  end

  @spec external_executor_strict?() :: boolean()
  defp external_executor_strict? do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:external_executor_strict, false)
  end

  @spec runtime_mode() :: RuntimeMode.t()
  defp runtime_mode do
    mode =
      Application.get_env(:ide, __MODULE__, [])
      |> Keyword.get(:runtime_mode, :runtime_first)

    case mode do
      :legacy -> :legacy
      "legacy" -> :legacy
      :hybrid -> :hybrid
      "hybrid" -> :hybrid
      :runtime_first -> :runtime_first
      "runtime_first" -> :runtime_first
      "runtime-first" -> :runtime_first
      _ -> :runtime_first
    end
  end

  @spec list_count(list() | nil) :: non_neg_integer()
  defp list_count(value) when is_list(value), do: length(value)
  defp list_count(_), do: 0

  @spec normalize_update_branches([String.t()] | nil) :: [String.t()]
  defp normalize_update_branches(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_update_branches(_), do: []

  @spec contains_any?(String.t(), [String.t()]) :: boolean()
  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, fn needle -> String.contains?(text, needle) end)
  end

  @spec operation_from_text(String.t()) ::
          :inc | :dec | :toggle | :enable | :disable | :reset | :tick
  defp operation_from_text(text) when is_binary(text) do
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

  @spec step_operation_for_message(String.t(), [String.t()]) ::
          :inc | :dec | :toggle | :enable | :disable | :reset | :tick
  defp step_operation_for_message(message, update_branches)
       when is_binary(message) and is_list(update_branches) do
    case operation_from_text(message) do
      :tick ->
        update_branches
        |> Enum.map(&operation_from_text/1)
        |> Enum.find(:tick, &(&1 != :tick))

      op ->
        op
    end
  end

  @spec mutate_runtime_model(Types.inner_runtime_model(), String.t(), [String.t()]) ::
          Types.inner_runtime_model()
  defp mutate_runtime_model(model, message, update_branches)
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

  @spec derive_step_view_tree(
          Types.view_output_tree(),
          Types.inner_runtime_model(),
          String.t(),
          :inc | :dec | :toggle | :enable | :disable | :reset | :tick,
          String.t()
        ) :: Types.view_output_tree()
  defp derive_step_view_tree(current_view_tree, runtime_model, message, op, source_root)
       when is_map(runtime_model) and is_binary(message) and is_atom(op) and
              is_binary(source_root) do
    base =
      if is_map(current_view_tree) and map_size(current_view_tree) > 0 do
        current_view_tree
      else
        %{"type" => "root", "children" => []}
      end

    children =
      case Map.get(base, "children") || Map.get(base, :children) do
        xs when is_list(xs) -> xs
        _ -> []
      end

    marker = %{
      "type" => "runtimeStep",
      "label" => "#{source_root}:#{message}",
      "op" => Atom.to_string(op),
      "model_entries" => map_size(runtime_model),
      "children" => []
    }

    base
    |> Map.put("children", [marker | children] |> Enum.take(12))
    |> Map.put("last_runtime_step_message", message)
    |> Map.put("last_runtime_step_op", Atom.to_string(op))
  end

  @spec view_tree_node_count(Types.view_output_tree() | map()) :: non_neg_integer()
  defp view_tree_node_count(%{"children" => children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{children: children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{}), do: 1
  defp view_tree_node_count(_), do: 0

  @spec stable_term_sha256(map() | list()) :: String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
