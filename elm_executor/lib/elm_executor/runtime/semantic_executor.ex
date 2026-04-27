defmodule ElmExecutor.Runtime.SemanticExecutor do
  @moduledoc """
  Deterministic in-process runtime semantics for elm_executor.

  This is intentionally independent from `Elmc.Runtime.Executor` so elm_executor
  remains a standalone backend/runtime surface.
  """
  @dialyzer :no_match

  alias ElmExecutor.Runtime.CoreIREvaluator

  @doc """
  Evaluates a parser-derived rendered view node against the current runtime model.

  This is used by debugger UI code to annotate the source-shaped rendered hierarchy
  with the same values the semantic executor can derive for visual preview output.
  """
  @spec evaluate_view_tree_value(term(), map(), map()) :: term()
  def evaluate_view_tree_value(node, runtime_model, eval_context \\ %{})

  def evaluate_view_tree_value(node, runtime_model, eval_context)
      when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    eval_tree_expr_value(node, runtime_model, eval_context)
  end

  def evaluate_view_tree_value(_node, _runtime_model, _eval_context), do: nil

  @spec execute(term()) :: {:ok, map()} | {:error, term()}
  def execute(request) when is_map(request) do
    source_root = map_value(request, :source_root) || "watch"
    rel_path = map_value(request, :rel_path)
    source = map_value(request, :source) || ""
    introspect = map_value(request, :introspect)
    introspect = if is_map(introspect), do: introspect, else: %{}
    current_model = map_value(request, :current_model)
    current_model = if is_map(current_model), do: current_model, else: %{}
    current_view_tree = map_value(request, :current_view_tree)
    current_view_tree = if is_map(current_view_tree), do: current_view_tree, else: %{}
    message = map_value(request, :message)
    core_ir = map_value(request, :elm_executor_core_ir)
    eval_context = evaluator_context(core_ir)

    base_runtime_model =
      case map_value(current_model, :runtime_model) do
        model when is_map(model) and map_size(model) > 0 ->
          model

        _ ->
          evaluated_init_model(core_ir, eval_context, current_model) ||
            map_value(introspect, :init_model) ||
            %{}
      end

    {runtime_model, runtime_model_source, op, operation_source, key_provenance} =
      case message do
        msg when is_binary(msg) and msg != "" ->
          case evaluate_update_from_core_ir(core_ir, eval_context, msg, base_runtime_model) do
            {:ok, updated_model, op, operation_source, key_provenance} ->
              updated =
                updated_model
                |> Map.put("last_message", branch_constructor_token(msg))
                |> Map.put("last_operation", Atom.to_string(op))

              {updated, "step_message", op, operation_source, key_provenance}

            :error ->
              updated =
                base_runtime_model
                |> Map.put("step_counter", Map.get(base_runtime_model, "step_counter", 0) + 1)
                |> Map.put("last_message", branch_constructor_token(msg))
                |> Map.put("last_operation", "nil")

              key_provenance = %{
                "numeric_key" => nil,
                "numeric_key_source" => nil,
                "boolean_key" => nil,
                "boolean_key_source" => nil,
                "string_key" => nil,
                "string_key_source" => nil,
                "active_key" => nil,
                "active_key_source" => nil
              }

              {updated, "step_message", nil, "unmapped_message", key_provenance}
          end

        _ ->
          {base_runtime_model, "init_model", nil, "init_model", %{}}
      end

    runtime_model_for_view = enrich_runtime_model_for_view(runtime_model, current_model)

    runtime_view_tree =
      derive_view_tree(
        current_view_tree,
        introspect,
        runtime_model_for_view,
        source_root,
        message,
        op,
        eval_context
      )

    followup_messages = package_followup_messages(request, introspect, source_root, message)

    view_output = derive_view_output(runtime_view_tree, runtime_model_for_view, eval_context)

    runtime = %{
      "engine" => "elm_executor_runtime_v1",
      "source_root" => source_root,
      "rel_path" => rel_path,
      "source_byte_size" => byte_size(source),
      "msg_constructor_count" => list_count(map_value(introspect, :msg_constructors)),
      "update_case_branch_count" => list_count(map_value(introspect, :update_case_branches)),
      "view_case_branch_count" => list_count(map_value(introspect, :view_case_branches)),
      "runtime_model_source" => runtime_model_source,
      "operation_source" => operation_source,
      "heuristic_fallback_used" => false,
      "view_tree_source" => view_tree_source(message),
      "target_numeric_key" => Map.get(key_provenance, "numeric_key"),
      "target_numeric_key_source" => Map.get(key_provenance, "numeric_key_source"),
      "target_boolean_key" => Map.get(key_provenance, "boolean_key"),
      "target_boolean_key_source" => Map.get(key_provenance, "boolean_key_source"),
      "active_target_key" => Map.get(key_provenance, "active_key"),
      "active_target_key_source" => Map.get(key_provenance, "active_key_source"),
      "followup_message_count" => length(followup_messages),
      "view_output_count" => length(view_output),
      "runtime_model_entry_count" => map_size(runtime_model),
      "view_tree_node_count" => view_tree_node_count(runtime_view_tree),
      "runtime_model_sha256" => stable_term_sha256(runtime_model),
      "view_tree_sha256" => stable_term_sha256(runtime_view_tree)
    }

    {:ok,
     %{
       model_patch: %{
         "runtime_model" => runtime_model,
         "runtime_model_source" => runtime_model_source,
         "runtime_model_sha256" => runtime["runtime_model_sha256"],
         "runtime_view_tree_sha256" => runtime["view_tree_sha256"],
         "runtime_view_output" => view_output,
         "elm_executor_mode" => "runtime_executed",
         "elm_executor" => runtime
       },
       view_tree: if(map_size(runtime_view_tree) > 0, do: runtime_view_tree, else: nil),
       view_output: view_output,
       runtime: runtime,
       protocol_events: protocol_events(source_root, message, op),
       followup_messages: followup_messages
     }}
  end

  def execute(_), do: {:error, :invalid_execution_request}

  @spec map_value(term(), term()) :: term()
  defp map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  @spec list_count(term()) :: non_neg_integer()
  defp list_count(value) when is_list(value), do: length(value)
  defp list_count(_), do: 0

  @spec evaluate_update_from_core_ir(term(), term(), term(), term()) ::
          {:ok, map(), atom() | nil, String.t(), map()} | :error
  defp evaluate_update_from_core_ir(core_ir, eval_context, message, runtime_model)
       when is_map(eval_context) and is_binary(message) and is_map(runtime_model) do
    with %{} = update_expr <- update_function_expr_from_core_ir(core_ir),
         {:ok, msg_value} <- parse_message_value(message),
         {:ok, result} <-
           CoreIREvaluator.evaluate(
             update_expr,
             %{"msg" => msg_value, "model" => runtime_model},
             eval_context
           ),
         {:ok, result_model} <- update_result_model(result) do
      next_model = Map.merge(runtime_model, result_model)
      {op, operation_source} = operation_from_model_delta(runtime_model, next_model)
      key_provenance = key_provenance_from_model_delta(runtime_model, next_model)
      {:ok, next_model, op, operation_source, key_provenance}
    else
      _ -> :error
    end
  end

  defp evaluate_update_from_core_ir(_core_ir, _eval_context, _message, _runtime_model), do: :error

  @spec update_function_expr_from_core_ir(term()) :: map() | nil
  defp update_function_expr_from_core_ir(%{modules: modules}) when is_list(modules),
    do: update_function_expr_from_core_ir(%{"modules" => modules})

  defp update_function_expr_from_core_ir(%{"modules" => modules}) when is_list(modules) do
    modules
    |> Enum.find_value(fn module ->
      declarations = module["declarations"] || module[:declarations] || []

      declarations
      |> Enum.find_value(fn decl ->
        name = decl["name"] || decl[:name]
        kind = decl["kind"] || decl[:kind]

        if name == "update" and (kind == "function" or kind == :function) do
          expr = decl["expr"] || decl[:expr]
          if is_map(expr), do: expr, else: nil
        else
          nil
        end
      end)
    end)
  end

  defp update_function_expr_from_core_ir(_), do: nil

  @spec evaluated_init_model(term(), term(), term()) :: map() | nil
  defp evaluated_init_model(_core_ir, eval_context, current_model)
       when is_map(eval_context) and is_map(current_model) do
    launch_context = map_value(current_model, :launch_context) || %{}

    candidates =
      if map_size(launch_context) > 0 do
        [
          %{"op" => :qualified_call, "target" => "Main.init", "args" => [launch_context]},
          %{"op" => :qualified_call, "target" => "init", "args" => [launch_context]},
          %{"op" => :qualified_call, "target" => "Main.init", "args" => []},
          %{"op" => :qualified_call, "target" => "init", "args" => []}
        ]
      else
        [
          %{"op" => :qualified_call, "target" => "Main.init", "args" => []},
          %{"op" => :qualified_call, "target" => "init", "args" => []}
        ]
      end

    Enum.find_value(candidates, fn expr ->
      with {:ok, result} <- CoreIREvaluator.evaluate(expr, %{}, eval_context),
           {:ok, model} <- update_result_model(result),
           true <- map_size(model) > 0 do
        model
      else
        _ -> nil
      end
    end)
  end

  defp evaluated_init_model(_core_ir, _eval_context, _current_model), do: nil

  @spec parse_message_value(term()) :: {:ok, map()} | :error
  defp parse_message_value(message) when is_binary(message) do
    constructor =
      message |> branch_constructor_token() |> unqualified_identifier() |> String.trim()

    if constructor == "" do
      :error
    else
      args =
        message
        |> message_argument_tail()
        |> parse_message_arguments([])
        |> Enum.map(&parse_message_argument_value/1)

      {:ok, %{"ctor" => constructor, "args" => args}}
    end
  end

  @spec message_argument_tail(String.t()) :: String.t()
  defp message_argument_tail(message) do
    constructor = branch_constructor_token(message)
    String.trim_leading(String.replace_prefix(String.trim(message), constructor, ""))
  end

  @spec parse_message_arguments(term(), [String.t()]) :: [String.t()]
  defp parse_message_arguments("", acc), do: Enum.reverse(acc)

  defp parse_message_arguments(text, acc) when is_binary(text) do
    text = String.trim_leading(text)

    if text == "" do
      Enum.reverse(acc)
    else
      {arg, rest} = take_single_argument(text)

      if arg == "" do
        Enum.reverse(acc)
      else
        parse_message_arguments(rest, [arg | acc])
      end
    end
  end

  @spec parse_message_argument_value(String.t()) :: term()
  defp parse_message_argument_value(token) when is_binary(token) do
    trimmed = String.trim(token)

    cond do
      trimmed == "True" or trimmed == "true" ->
        true

      trimmed == "False" or trimmed == "false" ->
        false

      String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") and
          String.length(trimmed) >= 2 ->
        trimmed
        |> String.slice(1, String.length(trimmed) - 2)
        |> String.replace("\\\"", "\"")
        |> String.replace("\\\\", "\\")

      String.starts_with?(trimmed, "(") and String.ends_with?(trimmed, ")") ->
        trimmed
        |> String.slice(1, String.length(trimmed) - 2)
        |> parse_constructor_message_argument()

      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, value} -> value
          _ -> parse_numeric_message_argument(trimmed)
        end

      true ->
        parse_numeric_message_argument(trimmed)
    end
  end

  @spec parse_constructor_message_argument(String.t()) :: term()
  defp parse_constructor_message_argument(value) when is_binary(value) do
    constructor = branch_constructor_token(value) |> unqualified_identifier() |> String.trim()

    if constructor == "" do
      value
    else
      args =
        value
        |> message_argument_tail()
        |> parse_message_arguments([])
        |> Enum.map(&parse_message_argument_value/1)

      %{"ctor" => constructor, "args" => args}
    end
  end

  @spec parse_numeric_message_argument(String.t()) :: term()
  defp parse_numeric_message_argument(trimmed) when is_binary(trimmed) do
    case Integer.parse(trimmed) do
      {value, ""} ->
        value

      _ ->
        case Float.parse(trimmed) do
          {value, ""} -> value
          _ -> trimmed
        end
    end
  end

  @spec update_result_model(term()) :: {:ok, map()} | :error
  defp update_result_model({left, _right}) when is_map(left), do: {:ok, left}
  defp update_result_model(model) when is_map(model), do: {:ok, model}
  defp update_result_model(_), do: :error

  @spec operation_from_model_delta(map(), map()) :: {atom() | nil, String.t()}
  defp operation_from_model_delta(previous_model, next_model)
       when is_map(previous_model) and is_map(next_model) do
    changed_keys =
      Map.keys(next_model)
      |> Enum.filter(fn key -> Map.get(previous_model, key) != Map.get(next_model, key) end)

    if changed_keys == [] do
      {nil, "core_ir_update_noop"}
    else
      {:set, "core_ir_update_eval"}
    end
  end

  @spec key_provenance_from_model_delta(map(), map()) :: map()
  defp key_provenance_from_model_delta(previous_model, next_model)
       when is_map(previous_model) and is_map(next_model) do
    changed_keys =
      Map.keys(next_model)
      |> Enum.filter(fn key -> Map.get(previous_model, key) != Map.get(next_model, key) end)

    active_key =
      case changed_keys do
        [key] -> to_string(key)
        _ -> nil
      end

    %{
      "numeric_key" => nil,
      "numeric_key_source" => nil,
      "boolean_key" => nil,
      "boolean_key_source" => nil,
      "string_key" => nil,
      "string_key_source" => nil,
      "active_key" => active_key,
      "active_key_source" => if(is_binary(active_key), do: "core_ir_delta", else: nil)
    }
  end

  @spec branch_constructor_token(String.t()) :: String.t()
  defp branch_constructor_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> Kernel.||("")
  end

  @spec take_single_argument(term()) :: {String.t(), String.t()}
  defp take_single_argument(<<first, _::binary>> = text) when first in [?(, ?[, ?{] do
    take_group_argument(text)
  end

  defp take_single_argument(<<"\"", _::binary>> = text) do
    take_quoted_argument(text)
  end

  defp take_single_argument(text) when is_binary(text) do
    case Regex.run(~r/^(\S+)(?:\s+(.*))?$/s, text, capture: :all_but_first) do
      [arg, rest] -> {arg, rest}
      [arg] -> {arg, ""}
      _ -> {"", ""}
    end
  end

  @spec take_quoted_argument(String.t()) :: {String.t(), String.t()}
  defp take_quoted_argument(<<"\"", rest::binary>>) do
    consume_quoted(rest, "\"", false)
  end

  @spec consume_quoted(String.t(), String.t(), boolean()) :: {String.t(), String.t()}
  defp consume_quoted(<<>>, acc, _escaped), do: {acc, ""}

  defp consume_quoted(<<char, rest::binary>>, acc, escaped) do
    acc = acc <> <<char>>

    cond do
      escaped ->
        consume_quoted(rest, acc, false)

      char == ?\\ ->
        consume_quoted(rest, acc, true)

      char == ?" ->
        {acc, rest}

      true ->
        consume_quoted(rest, acc, false)
    end
  end

  @spec take_group_argument(term()) :: term()
  defp take_group_argument(<<open, rest::binary>>) when open in [?(, ?[, ?{] do
    closer = matching_closer(open)
    consume_group(rest, [closer], <<open>>)
  end

  @spec consume_group(term(), term(), term()) :: term()
  defp consume_group(<<>>, _stack, acc), do: {acc, ""}
  defp consume_group(rest, [], acc), do: {acc, rest}

  defp consume_group(<<char, tail::binary>>, [char | stack_rest], acc) do
    acc = <<acc::binary, char>>

    if stack_rest == [] do
      {acc, tail}
    else
      consume_group(tail, stack_rest, acc)
    end
  end

  defp consume_group(<<char, tail::binary>>, stack, acc) do
    next_stack =
      case matching_closer(char) do
        nil -> stack
        closer -> [closer | stack]
      end

    consume_group(tail, next_stack, <<acc::binary, char>>)
  end

  @spec matching_closer(term()) :: integer() | nil
  defp matching_closer(?(), do: ?)
  defp matching_closer(?[), do: ?]
  defp matching_closer(?{), do: ?}
  defp matching_closer(_), do: nil

  @spec unqualified_identifier(String.t()) :: String.t()
  defp unqualified_identifier(value) when is_binary(value) do
    value
    |> String.split(".")
    |> List.last()
    |> Kernel.||(value)
  end

  @spec derive_view_tree(term(), term(), term(), term(), term(), term(), term()) :: term()
  defp derive_view_tree(
         current_view_tree,
         introspect,
         runtime_model,
         source_root,
         message,
         op,
         eval_context
       ) do
    evaluated_runtime_tree = evaluate_runtime_view_tree(eval_context, runtime_model)

    base =
      cond do
        is_map(evaluated_runtime_tree) and map_size(evaluated_runtime_tree) > 0 ->
          evaluated_runtime_tree

        not (is_binary(message) and message != "") and is_map(map_value(introspect, :view_tree)) ->
          map_value(introspect, :view_tree)

        is_map(current_view_tree) and map_size(current_view_tree) > 0 ->
          current_view_tree

        is_map(map_value(introspect, :view_tree)) ->
          map_value(introspect, :view_tree)

        true ->
          %{"type" => "root", "children" => []}
      end

    if is_binary(message) and is_atom(op) do
      children =
        case Map.get(base, "children") || Map.get(base, :children) do
          xs when is_list(xs) -> xs
          _ -> []
        end

      marker = %{
        "type" => "elmcRuntimeStep",
        "label" => "#{source_root}:#{message}",
        "op" => Atom.to_string(op),
        "model_entries" => map_size(runtime_model),
        "children" => []
      }

      base
      |> Map.put("children", [marker | children] |> Enum.take(12))
      |> Map.put("last_runtime_step_message", message)
      |> Map.put("last_runtime_step_op", Atom.to_string(op))
    else
      base
    end
  end

  @spec evaluate_runtime_view_tree(term(), term()) :: term()
  defp evaluate_runtime_view_tree(eval_context, runtime_model)
       when is_map(eval_context) and is_map(runtime_model) do
    expr = %{"op" => :qualified_call, "target" => "Main.view", "args" => [runtime_model]}

    case CoreIREvaluator.evaluate(expr, %{"model" => runtime_model}, eval_context) do
      {:ok, value} ->
        normalize_runtime_view_tree(value)

      _ ->
        %{}
    end
  end

  defp evaluate_runtime_view_tree(_eval_context, _runtime_model), do: %{}

  @spec normalize_runtime_view_tree(term()) :: term()
  defp normalize_runtime_view_tree(%{} = value) do
    type = value["type"] || value[:type]
    children = value["children"] || value[:children]

    cond do
      is_binary(type) and is_list(children) ->
        node = %{
          "type" => type,
          "label" => to_string(value["label"] || value[:label] || ""),
          "children" => Enum.map(children, &normalize_runtime_view_tree/1)
        }

        node =
          if Map.has_key?(value, "value"), do: Map.put(node, "value", value["value"]), else: node

        node =
          if Map.has_key?(value, :value), do: Map.put(node, "value", value[:value]), else: node

        node =
          if Map.has_key?(value, "op"),
            do: Map.put(node, "op", to_string(value["op"])),
            else: node

        node =
          if Map.has_key?(value, :op), do: Map.put(node, "op", to_string(value[:op])), else: node

        node =
          if Map.has_key?(value, "text"),
            do: Map.put(node, "text", to_string(value["text"])),
            else: node

        if Map.has_key?(value, :text),
          do: Map.put(node, "text", to_string(value[:text])),
          else: node

      Map.has_key?(value, "ctor") ->
        ctor = to_string(value["ctor"] || "")
        args = value["args"] || []

        %{
          "type" => ctor,
          "label" => "",
          "children" => Enum.map(List.wrap(args), &normalize_runtime_view_tree/1)
        }

      true ->
        %{"type" => "record", "label" => "", "children" => []}
    end
  end

  defp normalize_runtime_view_tree(list) when is_list(list) do
    %{
      "type" => "List",
      "label" => "[#{length(list)}]",
      "children" => Enum.map(list, &normalize_runtime_view_tree/1)
    }
  end

  defp normalize_runtime_view_tree({left, right}) do
    %{
      "type" => "tuple2",
      "label" => "",
      "children" => [normalize_runtime_view_tree(left), normalize_runtime_view_tree(right)]
    }
  end

  defp normalize_runtime_view_tree(value)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value) do
    %{"type" => "expr", "label" => to_string(value), "value" => value, "children" => []}
  end

  defp normalize_runtime_view_tree(_), do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec evaluator_context(term()) :: term()
  defp evaluator_context(core_ir) do
    %{
      module: "Main",
      source_module: "Main",
      functions: CoreIREvaluator.index_functions(core_ir)
    }
  end

  @spec enrich_runtime_model_for_view(term(), term()) :: term()
  defp enrich_runtime_model_for_view(runtime_model, current_model)
       when is_map(runtime_model) and is_map(current_model) do
    launch = map_value(current_model, :launch_context) || %{}
    screen = map_value(launch, :screen) || %{}

    width =
      map_value(screen, :width) ||
        map_value(current_model, :screen_width) ||
        map_value(current_model, :screenW)

    height =
      map_value(screen, :height) ||
        map_value(current_model, :screen_height) ||
        map_value(current_model, :screenH)

    shape = map_value(launch, :shape)

    is_round =
      case map_value(screen, :is_round) || map_value(screen, :isRound) do
        value when is_boolean(value) ->
          value

        _ ->
          cond do
            map_value(current_model, :isRound) in [true, false] ->
              map_value(current_model, :isRound)

            map_value(current_model, :shape) in ["round", "rect"] ->
              map_value(current_model, :shape) == "round"

            true ->
              shape == "round"
          end
      end

    runtime_model
    |> maybe_resolve_context_placeholder("screenW", width)
    |> maybe_resolve_context_placeholder("screenH", height)
    |> maybe_resolve_context_placeholder("isRound", is_round)
    |> maybe_put_missing("screenW", width)
    |> maybe_put_missing("screenH", height)
    |> maybe_put_missing("isRound", is_round)
  end

  defp enrich_runtime_model_for_view(runtime_model, _current_model) when is_map(runtime_model),
    do: runtime_model

  defp enrich_runtime_model_for_view(_runtime_model, _current_model), do: %{}

  @spec maybe_put_missing(term(), term(), term()) :: term()
  defp maybe_put_missing(map, key, value)
       when is_map(map) and is_binary(key) and (is_integer(value) or is_boolean(value)) do
    if Map.has_key?(map, key), do: map, else: Map.put(map, key, value)
  end

  defp maybe_put_missing(map, _key, _value) when is_map(map), do: map

  @spec maybe_resolve_context_placeholder(term(), term(), term()) :: term()
  defp maybe_resolve_context_placeholder(map, key, replacement)
       when is_map(map) and is_binary(key) and
              (is_integer(replacement) or is_boolean(replacement)) do
    value = Map.get(map, key)

    if context_placeholder_value?(value, key) do
      Map.put(map, key, replacement)
    else
      map
    end
  end

  defp maybe_resolve_context_placeholder(map, _key, _replacement) when is_map(map), do: map

  @spec context_placeholder_value?(term(), term()) :: boolean()
  defp context_placeholder_value?(%{} = value, key) when is_binary(key) do
    call = Map.get(value, "$call") || Map.get(value, :"$call")
    op = Map.get(value, "op") || Map.get(value, :op)

    ((Map.get(value, "$opaque") || Map.get(value, :"$opaque")) == true and
       to_string(op) == "field_access") or
      case {call, key} do
        {text, "screenW"} when is_binary(text) -> String.contains?(text, "context.screen.width")
        {text, "screenH"} when is_binary(text) -> String.contains?(text, "context.screen.height")
        {text, "isRound"} when is_binary(text) -> String.contains?(text, "context.screen.isRound")
        _ -> false
      end
  end

  defp context_placeholder_value?(_value, _key), do: false

  @spec derive_view_output(term(), term(), term()) :: term()
  defp derive_view_output(view_tree, runtime_model, eval_context)
       when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    view_tree
    |> collect_view_nodes()
    |> Enum.flat_map(&view_output_from_node(&1, runtime_model, eval_context))
  end

  defp derive_view_output(_view_tree, _runtime_model, _eval_context), do: []

  @spec collect_view_nodes(term()) :: [map()]
  defp collect_view_nodes(node) when is_map(node) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> list
        _ -> []
      end

    here = if is_binary(node["type"] || node[:type]), do: [node], else: []
    here ++ Enum.flat_map(Enum.filter(children, &is_map/1), &collect_view_nodes/1)
  end

  defp collect_view_nodes(_), do: []

  @spec view_output_from_node(term(), term(), term()) :: term()
  defp view_output_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type =
      node
      |> Map.get("type", Map.get(node, :type, ""))
      |> to_string()

    ints = node_int_args(node, runtime_model, eval_context)

    case type do
      "clear" ->
        case clear_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [color]} ->
            [%{"kind" => "clear", "color" => color}]

          :error ->
            [unresolved_view_output_row(node, type, ints, 1)]
        end

      "roundRect" ->
        case round_rect_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x, y, w, h, radius, fill]} ->
            [
              %{
                "kind" => "round_rect",
                "x" => x,
                "y" => y,
                "w" => w,
                "h" => h,
                "radius" => radius,
                "fill" => fill
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 6)]
        end

      "rect" ->
        case rect_color_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x, y, w, h, fill]} ->
            [%{"kind" => "rect", "x" => x, "y" => y, "w" => w, "h" => h, "fill" => fill}]

          :error ->
            [unresolved_view_output_row(node, type, ints, 5)]
        end

      "fillRect" ->
        case rect_color_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x, y, w, h, fill]} ->
            [%{"kind" => "fill_rect", "x" => x, "y" => y, "w" => w, "h" => h, "fill" => fill}]

          :error ->
            [unresolved_view_output_row(node, type, ints, 5)]
        end

      "line" ->
        case line_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x1, y1, x2, y2, color]} ->
            [
              %{
                "kind" => "line",
                "x1" => x1,
                "y1" => y1,
                "x2" => x2,
                "y2" => y2,
                "color" => color
              }
            ]

          _ ->
            [unresolved_view_output_row(node, type, ints, 5)]
        end

      "arc" ->
        case rect_angle_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                "kind" => "arc",
                "x" => x,
                "y" => y,
                "w" => w,
                "h" => h,
                "start_angle" => start_angle,
                "end_angle" => end_angle
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 6)]
        end

      "fillRadial" ->
        case rect_angle_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [x, y, w, h, start_angle, end_angle]} ->
            [
              %{
                "kind" => "fill_radial",
                "x" => x,
                "y" => y,
                "w" => w,
                "h" => h,
                "start_angle" => start_angle,
                "end_angle" => end_angle
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 6)]
        end

      "pathFilled" ->
        case path_args_from_node(node, runtime_model, eval_context) do
          {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
            [
              %{
                "kind" => "path_filled",
                "points" => points,
                "offset_x" => offset_x,
                "offset_y" => offset_y,
                "rotation" => rotation
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "pathOutline" ->
        case path_args_from_node(node, runtime_model, eval_context) do
          {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
            [
              %{
                "kind" => "path_outline",
                "points" => points,
                "offset_x" => offset_x,
                "offset_y" => offset_y,
                "rotation" => rotation
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "pathOutlineOpen" ->
        case path_args_from_node(node, runtime_model, eval_context) do
          {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}} ->
            [
              %{
                "kind" => "path_outline_open",
                "points" => points,
                "offset_x" => offset_x,
                "offset_y" => offset_y,
                "rotation" => rotation
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "circle" ->
        case circle_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [cx, cy, r, color]} ->
            [%{"kind" => "circle", "cx" => cx, "cy" => cy, "r" => r, "color" => color}]

          _ ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "fillCircle" ->
        case circle_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [cx, cy, r, color]} ->
            [%{"kind" => "fill_circle", "cx" => cx, "cy" => cy, "r" => r, "color" => color}]

          _ ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "bitmapInRect" ->
        case require_ints(ints, 5) do
          {:ok, [bitmap_id, x, y, w, h]} ->
            [
              %{
                "kind" => "bitmap_in_rect",
                "bitmap_id" => bitmap_id,
                "x" => x,
                "y" => y,
                "w" => w,
                "h" => h
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 5)]
        end

      "rotatedBitmap" ->
        case require_ints(ints, 6) do
          {:ok, [bitmap_id, src_w, src_h, angle, center_x, center_y]} ->
            [
              %{
                "kind" => "rotated_bitmap",
                "bitmap_id" => bitmap_id,
                "src_w" => src_w,
                "src_h" => src_h,
                "angle" => angle,
                "center_x" => center_x,
                "center_y" => center_y
              }
            ]

          :error ->
            [unresolved_view_output_row(node, type, ints, 6)]
        end

      "pixel" ->
        case require_ints(ints, 3) do
          {:ok, [x, y, color]} ->
            [%{"kind" => "pixel", "x" => x, "y" => y, "color" => color}]

          :error ->
            [unresolved_view_output_row(node, type, ints, 3)]
        end

      "textInt" ->
        case text_int_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [font_id, x, y, value]} when is_integer(font_id) and is_integer(value) ->
            [
              %{
                "kind" => "text_int",
                "x" => x,
                "y" => y,
                "text" => Integer.to_string(value),
                "font_id" => font_id
              }
            ]

          _ ->
            [unresolved_view_output_row(node, type, ints, 4)]
        end

      "textLabel" ->
        case text_label_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [font_id, x, y]} when is_integer(font_id) ->
            [
              %{
                "kind" => "text_label",
                "x" => x,
                "y" => y,
                "text" => text_label_from_node(node, runtime_model, eval_context),
                "font_id" => font_id
              }
            ]

          _ ->
            [unresolved_view_output_row(node, type, ints, 3)]
        end

      "text" ->
        case text_args_from_node(node, ints, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, text]}
          when is_integer(font_id) and is_integer(x) and is_integer(y) and is_integer(w) and
                 is_integer(h) and is_binary(text) ->
            [
              %{
                "kind" => "text",
                "x" => x,
                "y" => y,
                "w" => w,
                "h" => h,
                "text" => text,
                "font_id" => font_id
              }
            ]

          _ ->
            [unresolved_view_output_row(node, type, ints, 6)]
        end

      _ ->
        []
    end
  end

  defp view_output_from_node(_node, _runtime_model, _eval_context), do: []

  @spec node_int_args(term(), term(), term()) :: term()
  defp node_int_args(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    label = (node["label"] || node[:label] || "") |> to_string()
    from_label = extract_ints(label)
    min_arity = min_int_arity_for_node(node)

    if from_label != [] and length(from_label) >= min_arity do
      from_label
    else
      children =
        case node["children"] || node[:children] do
          list when is_list(list) -> list
          _ -> []
        end

      children
      |> Enum.filter(&is_map/1)
      |> Enum.map(&eval_view_int(&1, runtime_model, eval_context))
      |> Enum.reject(&is_nil/1)
    end
  end

  defp node_int_args(_node, _runtime_model, _eval_context), do: []

  @spec min_int_arity_for_node(term()) :: non_neg_integer()
  defp min_int_arity_for_node(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "clear" -> 1
      "roundRect" -> 6
      "rect" -> 5
      "fillRect" -> 5
      "line" -> 5
      "arc" -> 6
      "fillRadial" -> 6
      "pathFilled" -> 4
      "pathOutline" -> 4
      "pathOutlineOpen" -> 4
      "circle" -> 4
      "fillCircle" -> 4
      "bitmapInRect" -> 5
      "rotatedBitmap" -> 6
      "pixel" -> 3
      "textInt" -> 4
      "textLabel" -> 3
      _ -> 1
    end
  end

  @spec require_ints(term(), term()) :: {:ok, [integer()]} | :error
  defp require_ints(values, required)
       when is_list(values) and is_integer(required) and required > 0 do
    if length(values) >= required do
      head = Enum.take(values, required)
      if Enum.all?(head, &is_integer/1), do: {:ok, head}, else: :error
    else
      :error
    end
  end

  defp require_ints(_values, _required), do: :error

  @spec unresolved_view_output_row(term(), term(), term(), term()) :: term()
  defp unresolved_view_output_row(node, node_type, ints, required_arity)
       when is_map(node) and is_binary(node_type) and is_list(ints) and is_integer(required_arity) do
    %{
      "kind" => "unresolved",
      "node_type" => node_type,
      "label" => to_string(node["label"] || node[:label] || ""),
      "provided_int_count" => length(ints),
      "required_int_count" => required_arity
    }
  end

  @spec clear_args_from_node(term(), term(), term(), term()) :: term()
  defp clear_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 1) do
      {:ok, [color]} ->
        {:ok, [color]}

      :error ->
        case node_children(node) do
          [color_node | _] ->
            case eval_view_color(color_node, runtime_model, eval_context) do
              color when is_integer(color) -> {:ok, [color]}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp clear_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec line_args_from_node(term(), term(), term(), term()) :: term()
  defp line_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 5) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [start_node, end_node, color_node | _] ->
            with {:ok, [x1, y1]} <- point_pair_from_node(start_node, runtime_model, eval_context),
                 {:ok, [x2, y2]} <- point_pair_from_node(end_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x1, y1, x2, y2, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp line_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec circle_args_from_node(term(), term(), term(), term()) :: term()
  defp circle_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 4) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [center_node, radius_node, color_node | _] ->
            with {:ok, [cx, cy]} <-
                   point_pair_from_node(center_node, runtime_model, eval_context),
                 radius when is_integer(radius) <-
                   eval_view_int(radius_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [cx, cy, radius, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp circle_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec rect_color_args_from_node(term(), term(), term(), term()) :: term()
  defp rect_color_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 5) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [bounds_node, color_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp rect_color_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec round_rect_args_from_node(term(), term(), term(), term()) :: term()
  defp round_rect_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 6) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [bounds_node, radius_node, color_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 radius when is_integer(radius) <-
                   eval_view_int(radius_node, runtime_model, eval_context),
                 color when is_integer(color) <-
                   eval_view_color(color_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, radius, color]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp round_rect_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec rect_angle_args_from_node(term(), term(), term(), term()) :: term()
  defp rect_angle_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 6) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [bounds_node, start_node, end_node | _] ->
            with {:ok, [x, y, w, h]} <-
                   rect_quad_from_node(bounds_node, runtime_model, eval_context),
                 start_angle when is_integer(start_angle) <-
                   eval_view_int(start_node, runtime_model, eval_context),
                 end_angle when is_integer(end_angle) <-
                   eval_view_int(end_node, runtime_model, eval_context) do
              {:ok, [x, y, w, h, start_angle, end_angle]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp rect_angle_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec text_int_args_from_node(term(), term(), term(), term()) :: term()
  defp text_int_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 4) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [font_node, pos_node, value_node | _] ->
            with font_id when is_integer(font_id) <-
                   eval_view_font_id(font_node, runtime_model, eval_context),
                 {:ok, [x, y]} <- point_pair_from_node(pos_node, runtime_model, eval_context),
                 value when is_integer(value) <-
                   eval_view_int(value_node, runtime_model, eval_context) do
              {:ok, [font_id, x, y, value]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp text_int_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec text_label_args_from_node(term(), term(), term(), term()) :: term()
  defp text_label_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 3) do
      {:ok, args} ->
        {:ok, args}

      :error ->
        case node_children(node) do
          [font_node, pos_node | _] ->
            with font_id when is_integer(font_id) <-
                   eval_view_font_id(font_node, runtime_model, eval_context) do
              case point_pair_from_node(pos_node, runtime_model, eval_context) do
                {:ok, [x, y]} ->
                  {:ok, [font_id, x, y]}

                :error ->
                  pos_ints = node_int_args(pos_node, runtime_model, eval_context)

                  case require_ints(pos_ints, 2) do
                    {:ok, [x, y]} -> {:ok, [font_id, x, y]}
                    :error -> :error
                  end
              end
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp text_label_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec eval_view_font_id(term(), term(), term()) :: integer() | nil
  defp eval_view_font_id(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case eval_view_int(node, runtime_model, eval_context) do
      int when is_integer(int) ->
        int

      _ ->
        type =
          node
          |> Map.get("type", Map.get(node, :type, ""))
          |> to_string()
          |> String.downcase()

        label =
          node
          |> Map.get("label", Map.get(node, :label, ""))
          |> to_string()
          |> String.downcase()

        cond do
          String.contains?(type, "defaultfont") -> 0
          String.contains?(type, "uifont") -> 0
          String.contains?(label, "defaultfont") -> 0
          String.contains?(label, "uifont") -> 0
          true -> nil
        end
    end
  end

  defp eval_view_font_id(_node, _runtime_model, _eval_context), do: nil

  @spec rect_quad_from_node(term(), term(), term()) :: {:ok, [integer()]} | :error
  defp rect_quad_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "record" ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        x =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
          |> field_value_int(runtime_model, eval_context)

        y =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
          |> field_value_int(runtime_model, eval_context)

        w =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "w"))
          |> field_value_int(runtime_model, eval_context)

        h =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "h"))
          |> field_value_int(runtime_model, eval_context)

        if Enum.all?([x, y, w, h], &is_integer/1), do: {:ok, [x, y, w, h]}, else: :error

      _ ->
        :error
    end
  end

  defp rect_quad_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec path_args_from_node(term(), term(), term()) :: term()
  defp path_args_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> Enum.filter(list, &is_map/1)
        _ -> []
      end

    case children do
      [points_node, offset_x_node, offset_y_node, rotation_node | _] ->
        with {:ok, points} <- path_points_from_node(points_node, runtime_model, eval_context),
             offset_x when is_integer(offset_x) <-
               eval_view_int(offset_x_node, runtime_model, eval_context),
             offset_y when is_integer(offset_y) <-
               eval_view_int(offset_y_node, runtime_model, eval_context),
             rotation when is_integer(rotation) <-
               eval_view_int(rotation_node, runtime_model, eval_context) do
          {:ok, %{points: points, offset_x: offset_x, offset_y: offset_y, rotation: rotation}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp path_args_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec path_points_from_node(term(), term(), term()) :: term()
  defp path_points_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    cond do
      type == "List" ->
        children =
          case node["children"] || node[:children] do
            list when is_list(list) -> Enum.filter(list, &is_map/1)
            _ -> []
          end

        points =
          children
          |> Enum.map(&point_pair_from_node(&1, runtime_model, eval_context))

        if Enum.all?(points, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(points, fn {:ok, pair} -> pair end)}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp path_points_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec point_pair_from_node(term(), term(), term()) :: term()
  defp point_pair_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")
    op = to_string(node["op"] || node[:op] || "")

    case {type, op} do
      {"tuple2", _} ->
        children =
          case node["children"] || node[:children] do
            list when is_list(list) -> Enum.filter(list, &is_map/1)
            _ -> []
          end

        case children do
          [x_node, y_node | _] ->
            x = eval_view_int(x_node, runtime_model, eval_context)
            y = eval_view_int(y_node, runtime_model, eval_context)
            if is_integer(x) and is_integer(y), do: {:ok, [x, y]}, else: :error

          _ ->
            :error
        end

      {"record", _} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        x_value =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
          |> field_value_int(runtime_model, eval_context)

        y_value =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
          |> field_value_int(runtime_model, eval_context)

        if is_integer(x_value) and is_integer(y_value),
          do: {:ok, [x_value, y_value]},
          else: :error

      {"expr", "record_literal"} ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        x_value =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
          |> field_value_int(runtime_model, eval_context)

        y_value =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
          |> field_value_int(runtime_model, eval_context)

        if is_integer(x_value) and is_integer(y_value),
          do: {:ok, [x_value, y_value]},
          else: :error

      _ ->
        :error
    end
  end

  defp point_pair_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec field_value_int(term(), term(), term()) :: integer() | nil
  defp field_value_int(field_node, runtime_model, eval_context)
       when is_map(field_node) and is_map(runtime_model) and is_map(eval_context) do
    case node_children(field_node) do
      [value_node | _] -> eval_view_int(value_node, runtime_model, eval_context)
      _ -> nil
    end
  end

  defp field_value_int(_field_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_color(term(), term(), term()) :: integer() | nil
  defp eval_view_color(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case eval_view_int(node, runtime_model, eval_context) do
      int when is_integer(int) ->
        int

      _ ->
        color_name =
          node
          |> Map.get("type", Map.get(node, :type, ""))
          |> to_string()
          |> String.trim()
          |> String.downcase()

        case color_name do
          "clearcolor" -> 0x00
          "black" -> 0xC0
          "white" -> 0xFF
          _ -> nil
        end
    end
  end

  defp eval_view_color(_node, _runtime_model, _eval_context), do: nil

  @spec node_children(term()) :: [map()]
  defp node_children(node) when is_map(node) do
    case node["children"] || node[:children] do
      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      _ ->
        type = to_string(node["type"] || node[:type] || "")
        op = to_string(node["op"] || node[:op] || "")
        fields = node["fields"] || node[:fields]

        if (type == "record" or (type == "expr" and op == "record_literal")) and is_map(fields) do
          fields
          |> Enum.map(fn {k, v} ->
            child =
              cond do
                is_map(v) -> v
                is_integer(v) -> %{"type" => "expr", "value" => v}
                is_float(v) -> %{"type" => "expr", "value" => trunc(v)}
                is_binary(v) -> %{"type" => "expr", "label" => v}
                true -> %{"type" => "expr", "label" => to_string(v)}
              end

            %{
              "type" => "field",
              "label" => to_string(k),
              "children" => [child]
            }
          end)
        else
          []
        end
    end
  end

  @spec eval_view_int(term(), term(), term()) :: integer() | nil
  defp eval_view_int(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    val = node["value"] || node[:value]

    cond do
      is_integer(val) ->
        val

      is_float(val) ->
        trunc(val)

      is_binary(val) ->
        case Integer.parse(val) do
          {parsed, ""} -> parsed
          _ -> eval_view_int_fallback(node, runtime_model, eval_context)
        end

      true ->
        eval_view_int_fallback(node, runtime_model, eval_context)
    end
  end

  defp eval_view_int(_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_int_fallback(term(), term(), term()) :: term()
  defp eval_view_int_fallback(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")

    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> Enum.filter(list, &is_map/1)
        _ -> []
      end

    expr_eval = eval_tree_expr_int(node, runtime_model, eval_context)

    cond do
      is_integer(expr_eval) ->
        expr_eval

      (type == "expr" and op == "field_access") or String.starts_with?(label, "model.") ->
        label
        |> String.replace_prefix("model.", "")
        |> then(&Map.get(runtime_model, &1))
        |> case do
          value when is_integer(value) -> value
          value when is_float(value) -> trunc(value)
          _ -> nil
        end

      type == "var" ->
        case Map.get(runtime_model, label) do
          value when is_integer(value) -> value
          value when is_float(value) -> trunc(value)
          _ -> Enum.find_value(children, &eval_view_int(&1, runtime_model, eval_context))
        end

      type == "call" ->
        args = Enum.map(children, &eval_view_int(&1, runtime_model, eval_context))

        if Enum.all?(args, &is_integer/1) do
          eval_int_call(label, args)
        else
          nil
        end

      true ->
        Enum.find_value(children, &eval_view_int(&1, runtime_model, eval_context))
    end
  end

  defp eval_view_int_fallback(_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_text(term(), term(), term()) :: String.t() | nil
  defp eval_view_text(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    value = node["value"] || node[:value]
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")

    from_field_access =
      cond do
        op == "field_access" and String.starts_with?(label, "model.") ->
          key = String.replace_prefix(label, "model.", "")
          model_value_by_key(runtime_model, key)

        true ->
          nil
      end

    from_expr = eval_tree_expr_value(node, runtime_model, eval_context)

    from_children =
      Enum.find_value(node_children(node), &eval_view_text(&1, runtime_model, eval_context))

    [value, from_expr, from_field_access, from_children]
    |> Enum.find_value(&normalize_text_value/1)
  end

  defp eval_view_text(_node, _runtime_model, _eval_context), do: nil

  @spec eval_tree_expr_value(term(), term(), term()) :: term()
  defp eval_tree_expr_value(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        env = Map.put(runtime_model, "model", runtime_model)

        case CoreIREvaluator.evaluate(expr, env, eval_context) do
          {:ok, value} -> value
          _ -> nil
        end
    end
  end

  defp eval_tree_expr_value(_node, _runtime_model, _eval_context), do: nil

  @spec normalize_text_value(term()) :: String.t() | nil
  defp normalize_text_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: value, else: nil
  end

  defp normalize_text_value(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_text_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp normalize_text_value(_value), do: nil

  @spec model_value_by_key(map(), String.t()) :: term()
  defp model_value_by_key(model, key) when is_map(model) and is_binary(key) do
    Map.get(model, key) ||
      Enum.find_value(model, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value, else: nil

        _ ->
          nil
      end)
  end

  @spec eval_tree_expr_int(term(), term(), term()) :: term()
  defp eval_tree_expr_int(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        env = Map.put(runtime_model, "model", runtime_model)

        case CoreIREvaluator.evaluate(expr, env, eval_context) do
          {:ok, value} when is_integer(value) -> value
          {:ok, value} when is_float(value) -> trunc(value)
          _ -> nil
        end
    end
  end

  defp eval_tree_expr_int(_node, _runtime_model, _eval_context), do: nil

  @spec tree_node_to_expr(term()) :: term()
  defp tree_node_to_expr(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")
    value = node["value"] || node[:value]
    children = (node["children"] || node[:children] || []) |> Enum.filter(&is_map/1)

    cond do
      type == "var" and children != [] ->
        tree_node_to_expr(hd(children))

      type == "var" and label != "" ->
        %{"op" => :var, "name" => label}

      type == "call" and label != "" ->
        %{"op" => :call, "name" => label, "args" => Enum.map(children, &tree_node_to_expr/1)}

      type == "expr" and op == "tuple2" and length(children) >= 2 ->
        left = tree_node_to_expr(Enum.at(children, 0))
        right = tree_node_to_expr(Enum.at(children, 1))

        if is_map(left) and is_map(right) do
          %{"op" => :tuple2, "left" => left, "right" => right}
        else
          nil
        end

      type == "expr" and op == "tuple_first_expr" and children != [] ->
        case tree_node_to_expr(hd(children)) do
          nil -> nil
          arg_expr -> %{"op" => :tuple_first_expr, "arg" => arg_expr}
        end

      type == "expr" and op == "tuple_second_expr" and children != [] ->
        case tree_node_to_expr(hd(children)) do
          nil -> nil
          arg_expr -> %{"op" => :tuple_second_expr, "arg" => arg_expr}
        end

      type == "expr" and op == "field_access" and String.starts_with?(label, "model.") ->
        %{
          "op" => :field_access,
          "arg" => %{"op" => :var, "name" => "model"},
          "field" => String.replace_prefix(label, "model.", "")
        }

      type == "expr" and op == "string_literal" and is_binary(value) ->
        %{"op" => :string_literal, "value" => value}

      type == "expr" and op == "int_literal" and is_integer(value) ->
        %{"op" => :int_literal, "value" => value}

      type == "expr" and is_integer(value) ->
        %{"op" => :int_literal, "value" => value}

      type == "expr" and is_binary(label) ->
        case Integer.parse(label) do
          {parsed, ""} -> %{"op" => :int_literal, "value" => parsed}
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp tree_node_to_expr(_), do: nil

  @spec eval_int_call(term(), term()) :: term()
  defp eval_int_call("__add__", [a, b]), do: a + b
  defp eval_int_call("__sub__", [a, b]), do: a - b
  defp eval_int_call("__mul__", [a, b]), do: a * b
  defp eval_int_call("__idiv__", [_a, 0]), do: nil
  defp eval_int_call("__idiv__", [a, b]), do: div(a, b)

  defp eval_int_call("modBy", [by, value]) when is_integer(by) and by > 0 and is_integer(value),
    do: Integer.mod(value, by)

  defp eval_int_call("Basics.modBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: Integer.mod(value, by)

  defp eval_int_call("basics.modby", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: Integer.mod(value, by)

  defp eval_int_call("max", [a, b]), do: max(a, b)
  defp eval_int_call("min", [a, b]), do: min(a, b)
  defp eval_int_call(_name, _args), do: nil

  @spec extract_ints(term()) :: term()
  defp extract_ints(text) when is_binary(text) do
    Regex.scan(~r/-?\d+/, text)
    |> Enum.map(fn [raw] -> String.to_integer(raw) end)
  end

  @spec text_label_from_node(term(), term(), term()) :: term()
  defp text_label_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    child_text =
      case node_children(node) do
        [_font_node, _pos_node, label_node | _] ->
          eval_view_text(label_node, runtime_model, eval_context)

        _ ->
          nil
      end

    if is_binary(child_text) and String.trim(child_text) != "" do
      child_text
    else
      label = (node["label"] || node[:label] || "") |> to_string()

      case Regex.run(~r/^\s*-?\d+\s*,\s*-?\d+\s*,\s*(.+)\s*$/, label) do
        [_, text] ->
          text = String.trim(text)
          if byte_size(text) > 0, do: text, else: "Label"

        _ ->
          "Label"
      end
    end
  end

  defp text_label_from_node(_node, _runtime_model, _eval_context), do: "Label"

  @spec text_args_from_node(term(), term(), term(), term()) :: term()
  defp text_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 5) do
      {:ok, [font_id, x, y, w, h | _]} ->
        case node_children(node) do
          [_font_node, _x_node, _y_node, _w_node, _h_node, text_node | _] ->
            text =
              eval_view_text(text_node, runtime_model, eval_context) ||
                text_node
                |> Map.get("label")
                |> normalize_text_value() ||
                ""

            {:ok, [font_id, x, y, w, h, text]}

          _ ->
            :error
        end

      :error ->
        :error
    end
  end

  defp text_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec view_tree_source(term()) :: term()
  defp view_tree_source(message) when is_binary(message) and message != "",
    do: "step_derived_view_tree"

  defp view_tree_source(_), do: "parser_view_tree"

  @spec protocol_events(term(), term(), term()) :: term()
  defp protocol_events(_source_root, _message, _op), do: []

  @spec package_followup_messages(term(), term(), term(), term()) :: term()
  defp package_followup_messages(request, introspect, source_root, current_message)
       when is_map(request) and is_map(introspect) and is_binary(source_root) do
    if source_root in ["protocol", "companion", "phone"] and is_binary(current_message) and
         current_message != "" do
      current_ctor = message_constructor(current_message)
      result_types = http_callback_result_types(map_value(request, :source))

      cmd_calls_for_request(request, introspect, current_message)
      |> Enum.flat_map(
        &followup_messages_for_cmd_call(&1, source_root, current_ctor, result_types)
      )
      |> Enum.uniq_by(fn row -> Map.get(row, "message") end)
    else
      []
    end
  end

  defp package_followup_messages(_request, _introspect, _source_root, _current_message), do: []

  @spec cmd_calls_for_request(term(), term(), term()) :: term()
  defp cmd_calls_for_request(request, introspect, current_message)
       when is_map(request) and is_map(introspect) do
    explicit_calls =
      case map_value(request, :cmd_calls) do
        rows when is_list(rows) -> rows
        _ -> []
      end

    introspect_calls =
      if is_binary(current_message) and current_message != "" do
        map_value(introspect, :update_cmd_calls) || []
      else
        map_value(introspect, :init_cmd_calls) || []
      end

    (explicit_calls ++ introspect_calls)
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn row ->
      %{
        "target" => Map.get(row, "target") || Map.get(row, :target),
        "name" => Map.get(row, "name") || Map.get(row, :name),
        "callback_constructor" =>
          Map.get(row, "callback_constructor") || Map.get(row, :callback_constructor)
      }
    end)
  end

  defp cmd_calls_for_request(_request, _introspect, _current_message), do: []

  @spec followup_messages_for_cmd_call(term(), term(), term(), term()) :: term()
  defp followup_messages_for_cmd_call(cmd_call, source_root, current_ctor, result_types)
       when is_map(cmd_call) and is_binary(source_root) do
    name = cmd_call["name"] |> to_string() |> String.downcase()
    target = cmd_call["target"] |> to_string() |> String.downcase()
    callback = cmd_call["callback_constructor"]

    cond do
      callback in [nil, ""] ->
        []

      elm_http_command?(target, name) ->
        followup_callback_row(callback, current_ctor, source_root, "elm/http", result_types)

      true ->
        []
    end
  end

  defp followup_messages_for_cmd_call(_cmd_call, _source_root, _current_ctor, _result_types),
    do: []

  @spec elm_http_command?(String.t(), String.t()) :: boolean()
  defp elm_http_command?(target, name) when is_binary(target) and is_binary(name) do
    String.contains?(target, "http.") and name in ["get", "post", "request", "send"]
  end

  @spec followup_callback_row(term(), term(), term(), term(), term()) :: term()
  defp followup_callback_row(callback, current_ctor, source_root, package, result_types)
       when is_binary(callback) and is_binary(source_root) and is_binary(package) do
    if callback == "" or callback == current_ctor do
      []
    else
      payload = ok_payload_for_callback(callback, result_types)

      [
        %{
          "message" => "#{callback} (Ok #{payload})",
          "source_root" => source_root,
          "source" => "package_cmd",
          "package" => package,
          "result" => "Ok",
          "payload" => payload
        }
      ]
    end
  end

  defp followup_callback_row(_callback, _current_ctor, _source_root, _package, _result_types),
    do: []

  @spec http_callback_result_types(term()) :: map()
  defp http_callback_result_types(source) when is_binary(source) do
    ~r/(?:^|\n)\s*(?:=|\|)\s+([A-Z][A-Za-z0-9_]*)\s+\(Result\s+[A-Za-z0-9_.]+\s+([A-Za-z0-9_.]+)\)/m
    |> Regex.scan(source)
    |> Map.new(fn [_all, ctor, type] -> {ctor, type} end)
  end

  defp http_callback_result_types(_), do: %{}

  @spec ok_payload_for_callback(String.t(), map()) :: String.t()
  defp ok_payload_for_callback(callback, result_types) when is_map(result_types) do
    case Map.get(result_types, callback) do
      "Float" -> "21.5"
      "Int" -> "200"
      "Bool" -> "True"
      "String" -> inspect("debugger response")
      _ -> inspect("debugger response")
    end
  end

  @spec message_constructor(term()) :: term()
  defp message_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  defp message_constructor(_), do: nil

  @spec view_tree_node_count(term()) :: term()
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

  @spec stable_term_sha256(term()) :: term()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
