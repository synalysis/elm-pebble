defmodule ElmExecutor.Runtime.SemanticExecutor do
  @moduledoc """
  Deterministic in-process runtime semantics for elm_executor.

  This is intentionally independent from `Elmc.Runtime.Executor` so elm_executor
  remains a standalone backend/runtime surface.
  """
  @dialyzer :no_match

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
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
    message_value = map_value(request, :message_value)

    artifact_core_ir = map_value(request, :elm_executor_core_ir)
    core_ir = source_core_ir_fallback(artifact_core_ir, source, rel_path)
    eval_context = evaluator_context(core_ir)
    artifact_eval_context = evaluator_context(artifact_core_ir)
    static_init_model = map_value(introspect, :init_model)

    base_runtime_model =
      case map_value(current_model, :runtime_model) do
        model when is_map(model) and map_size(model) > 0 ->
          model

        _ ->
          evaluated_init_model_if_static_unresolved(
            core_ir,
            eval_context,
            current_model,
            static_init_model
          ) ||
            static_init_model ||
            %{}
      end

    {runtime_model, runtime_model_source, op, operation_source, key_provenance, runtime_commands} =
      case message do
        msg when is_binary(msg) and msg != "" ->
          case evaluate_update_from_core_ir(
                 artifact_core_ir,
                 artifact_eval_context,
                 msg,
                 message_value,
                 base_runtime_model
               ) do
            {:ok, updated_model, commands, op, operation_source, key_provenance} ->
              updated =
                updated_model
                |> Map.put("last_message", branch_constructor_token(msg))
                |> Map.put("last_operation", Atom.to_string(op))

              {updated, "step_message", op, operation_source, key_provenance, commands}

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

              {updated, "step_message", nil, "unmapped_message", key_provenance, []}
          end

        _ ->
          init_commands = init_runtime_commands(eval_context, current_model)

          {base_runtime_model, "init_model", nil, "init_model", %{}, init_commands}
      end

    runtime_model = normalize_runtime_model_by_declared_type(runtime_model, eval_context)
    runtime_model_for_view = enrich_runtime_model_for_view(runtime_model, current_model)
    init_execution? = not (is_binary(message) and message != "")

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

    followup_messages = package_followup_messages(runtime_commands, source_root)

    view_output =
      runtime_view_tree
      |> derive_view_output(runtime_model_for_view, eval_context)
      |> annotate_view_output_sources(introspect)

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
      "init_cmd_count" => if(init_execution?, do: meaningful_init_cmd_count(introspect), else: 0),
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
       protocol_events: protocol_events(source_root, runtime_commands),
       followup_messages: followup_messages
     }}
  end

  def execute(_), do: {:error, :invalid_execution_request}

  @spec map_value(term(), term()) :: term()
  defp map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  @spec generic_map_value(term(), String.t()) :: term()
  defp generic_map_value(map, key) when is_map(map) and is_binary(key) do
    map = if Map.has_key?(map, :__struct__), do: Map.from_struct(map), else: map

    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          nil -> nil
        end
    end
  end

  defp generic_map_value(_map, _key), do: nil

  @spec list_count(term()) :: non_neg_integer()
  defp list_count(value) when is_list(value), do: length(value)
  defp list_count(_), do: 0

  @spec meaningful_init_cmd_count(term()) :: non_neg_integer()
  defp meaningful_init_cmd_count(introspect) do
    introspect
    |> map_value(:init_cmd_calls)
    |> case do
      calls when is_list(calls) -> calls
      _ -> []
    end
    |> Enum.count(&meaningful_init_cmd_call?/1)
  end

  @spec meaningful_init_cmd_call?(term()) :: boolean()
  defp meaningful_init_cmd_call?(call) when is_map(call) do
    target = map_value(call, :target)
    name = map_value(call, :name)
    not (target in ["Cmd.none", "Platform.Cmd.none"] or name in ["none", "None", nil])
  end

  defp meaningful_init_cmd_call?(_call), do: false

  @spec evaluate_update_from_core_ir(term(), term(), term(), term(), term()) ::
          {:ok, map(), [map()], atom() | nil, String.t(), map()} | :error
  defp evaluate_update_from_core_ir(core_ir, eval_context, message, message_value, runtime_model)
       when is_map(eval_context) and is_binary(message) and is_map(runtime_model) do
    with %{} = update_expr <- update_function_expr_from_core_ir(core_ir),
         {:ok, msg_value} <- parse_message_value(message, message_value),
         env = %{"msg" => msg_value, "model" => runtime_model},
         {:ok, result} <- evaluate_model_command_result(update_expr, env, eval_context),
         {:ok, result_model} <- update_result_model(result) do
      next_model = Map.merge(runtime_model, result_model)
      {op, operation_source} = operation_from_model_delta(runtime_model, next_model)
      key_provenance = key_provenance_from_model_delta(runtime_model, next_model)
      {:ok, next_model, update_result_commands(result), op, operation_source, key_provenance}
    else
      _ -> :error
    end
  end

  defp evaluate_update_from_core_ir(
         _core_ir,
         _eval_context,
         _message,
         _message_value,
         _runtime_model
       ),
       do: :error

  @spec evaluated_init_model_if_static_unresolved(term(), term(), term(), term()) :: map() | nil
  defp evaluated_init_model_if_static_unresolved(
         core_ir,
         eval_context,
         current_model,
         static_init_model
       )
       when is_map(static_init_model) do
    if unresolved_runtime_value?(static_init_model) do
      evaluated_init_model(core_ir, eval_context, current_model)
    end
  end

  defp evaluated_init_model_if_static_unresolved(
         core_ir,
         eval_context,
         current_model,
         _static_init_model
       ),
       do: evaluated_init_model(core_ir, eval_context, current_model)

  defp unresolved_runtime_value?(%{"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{:"$opaque" => true}), do: true
  defp unresolved_runtime_value?(%{"$var" => name}) when is_binary(name), do: true
  defp unresolved_runtime_value?(%{:"$var" => name}) when is_binary(name), do: true

  defp unresolved_runtime_value?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, nested} -> unresolved_runtime_value?(nested) end)

  defp unresolved_runtime_value?(value) when is_list(value),
    do: Enum.any?(value, &unresolved_runtime_value?/1)

  defp unresolved_runtime_value?(_value), do: false

  @spec update_function_expr_from_core_ir(term()) :: map() | nil
  defp update_function_expr_from_core_ir(%{modules: modules}) when is_list(modules),
    do: update_function_expr_from_core_ir(%{"modules" => modules})

  defp update_function_expr_from_core_ir(%{"modules" => modules}) when is_list(modules) do
    modules
    |> Enum.find_value(fn module ->
      declarations = generic_map_value(module, "declarations") || []

      declarations
      |> Enum.find_value(fn decl ->
        name = generic_map_value(decl, "name")
        kind = generic_map_value(decl, "kind")

        if name == "update" and (kind == "function" or kind == :function) do
          expr = generic_map_value(decl, "expr")
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
    launch_context = current_model |> map_value(:launch_context) |> normalize_launch_context()

    candidates = [
      %{"op" => :qualified_call, "target" => "Main.init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "Main.init", "args" => []},
      %{"op" => :qualified_call, "target" => "init", "args" => []}
    ]

    Enum.find_value(candidates, fn expr ->
      with {:ok, result} <- CoreIREvaluator.evaluate(expr, %{}, eval_context),
           {:ok, model} <- update_result_model(result),
           true <- map_size(model) > 0 do
        model
      else
        _ -> nil
      end
    end) || evaluated_init_model_from_projected_expr(eval_context, launch_context)
  end

  defp evaluated_init_model(_core_ir, _eval_context, _current_model), do: nil

  @spec evaluated_init_model_from_projected_expr(term(), term()) :: map() | nil
  defp evaluated_init_model_from_projected_expr(eval_context, launch_context)
       when is_map(eval_context) and is_map(launch_context) do
    eval_context
    |> function_defs_named("init")
    |> Enum.find_value(fn %{params: params, body: body} ->
      values = if params == [], do: [], else: [launch_context]
      env = Enum.zip(params, values) |> Map.new()

      with %{} = model_expr <- project_model_result_expr(body),
           {:ok, model} <- CoreIREvaluator.evaluate(model_expr, env, eval_context),
           true <- is_map(model) and map_size(model) > 0 do
        model
      else
        _ -> nil
      end
    end)
  end

  defp evaluated_init_model_from_projected_expr(_eval_context, _launch_context), do: nil

  @spec init_runtime_commands(term(), map()) :: [map()]
  defp init_runtime_commands(eval_context, current_model)
       when is_map(eval_context) and is_map(current_model) do
    launch_context = current_model |> map_value(:launch_context) |> normalize_launch_context()

    candidates = [
      %{"op" => :qualified_call, "target" => "Main.init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "Main.init", "args" => []},
      %{"op" => :qualified_call, "target" => "init", "args" => []}
    ]

    Enum.find_value(candidates, fn expr ->
      with {:ok, result} <- CoreIREvaluator.evaluate(expr, %{}, eval_context),
           cmds when cmds != [] <- update_result_commands(result) do
        cmds
      else
        _ -> nil
      end
    end) || init_runtime_commands_from_projected_expr(eval_context, launch_context)
  end

  defp init_runtime_commands(_eval_context, _current_model), do: []

  @spec init_runtime_commands_from_projected_expr(term(), term()) :: [map()]
  defp init_runtime_commands_from_projected_expr(eval_context, launch_context)
       when is_map(eval_context) and is_map(launch_context) do
    eval_context
    |> function_defs_named("init")
    |> Enum.find_value(fn %{params: params, body: body} ->
      values = if params == [], do: [], else: [launch_context]
      env = Enum.zip(params, values) |> Map.new()

      case CoreIREvaluator.evaluate(body, env, eval_context) do
        {:ok, result} ->
          case update_result_commands(result) do
            [] -> nil
            cmds -> cmds
          end

        {:error, _} ->
          with %{} = cmd_expr <- project_cmd_result_expr(body),
               {:ok, cmd} <- CoreIREvaluator.evaluate(cmd_expr, env, eval_context),
               cmds when cmds != [] <- flatten_runtime_commands(cmd) do
            cmds
          else
            _ -> nil
          end
      end
    end) || []
  end

  defp init_runtime_commands_from_projected_expr(_eval_context, _launch_context), do: []

  @spec project_cmd_result_expr(term()) :: map() | nil
  defp project_cmd_result_expr(%{"op" => "tuple2", "right" => right}) when is_map(right),
    do: right

  defp project_cmd_result_expr(%{"op" => :tuple2, "right" => right}) when is_map(right), do: right
  defp project_cmd_result_expr(%{op: :tuple2, right: right}) when is_map(right), do: right

  defp project_cmd_result_expr(%{"op" => "tuple", "elements" => [_model, cmd | _]})
       when is_map(cmd),
       do: cmd

  defp project_cmd_result_expr(%{op: :tuple, elements: [_model, cmd | _]}) when is_map(cmd),
    do: cmd

  defp project_cmd_result_expr(_expr), do: nil

  @spec evaluate_model_command_result(term(), term(), term()) :: {:ok, term()} | {:error, term()}
  defp evaluate_model_command_result(expr, env, eval_context)
       when is_map(expr) and is_map(env) and is_map(eval_context) do
    case CoreIREvaluator.evaluate(expr, env, eval_context) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} = error ->
        case project_model_result_expr(expr) do
          %{} = model_expr -> CoreIREvaluator.evaluate(model_expr, env, eval_context)
          _ -> error
        end
    end
  end

  @spec function_defs_named(term(), String.t()) :: [map()]
  defp function_defs_named(eval_context, name) when is_map(eval_context) and is_binary(name) do
    eval_context
    |> Map.get(:functions, %{})
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, :name) == name))
    |> Enum.sort_by(&(length(Map.get(&1, :params, [])) != 1))
  end

  @spec project_model_result_expr(term()) :: map() | nil
  defp project_model_result_expr(%{"op" => :tuple2, "left" => left}) when is_map(left), do: left
  defp project_model_result_expr(%{op: :tuple2, left: left}) when is_map(left), do: left

  defp project_model_result_expr(%{"op" => :tuple, "elements" => [first | _]}) when is_map(first),
    do: first

  defp project_model_result_expr(%{op: :tuple, elements: [first | _]}) when is_map(first),
    do: first

  defp project_model_result_expr(%{"op" => :case, "branches" => branches} = expr)
       when is_list(branches) do
    Map.put(expr, "branches", Enum.map(branches, &project_case_branch_model_result/1))
  end

  defp project_model_result_expr(%{op: :case, branches: branches} = expr)
       when is_list(branches) do
    Map.put(expr, :branches, Enum.map(branches, &project_case_branch_model_result/1))
  end

  defp project_model_result_expr(%{"op" => :let_in, "in_expr" => in_expr} = expr)
       when is_map(in_expr) do
    case project_model_result_expr(in_expr) do
      %{} = projected -> Map.put(expr, "in_expr", projected)
      _ -> expr
    end
  end

  defp project_model_result_expr(%{op: :let_in, in_expr: in_expr} = expr) when is_map(in_expr) do
    case project_model_result_expr(in_expr) do
      %{} = projected -> Map.put(expr, :in_expr, projected)
      _ -> expr
    end
  end

  defp project_model_result_expr(%{"op" => :if} = expr) do
    expr
    |> maybe_project_branch_expr("then_expr")
    |> maybe_project_branch_expr("else_expr")
  end

  defp project_model_result_expr(%{op: :if} = expr) do
    expr
    |> maybe_project_branch_expr(:then_expr)
    |> maybe_project_branch_expr(:else_expr)
  end

  defp project_model_result_expr(expr) when is_map(expr), do: expr
  defp project_model_result_expr(_expr), do: nil

  defp project_case_branch_model_result(%{"expr" => expr} = branch) when is_map(expr) do
    case project_model_result_expr(expr) do
      %{} = projected -> Map.put(branch, "expr", projected)
      _ -> branch
    end
  end

  defp project_case_branch_model_result(%{expr: expr} = branch) when is_map(expr) do
    case project_model_result_expr(expr) do
      %{} = projected -> Map.put(branch, :expr, projected)
      _ -> branch
    end
  end

  defp project_case_branch_model_result(branch), do: branch

  defp maybe_project_branch_expr(expr, key) when is_map(expr) do
    case Map.get(expr, key) do
      branch_expr when is_map(branch_expr) ->
        case project_model_result_expr(branch_expr) do
          %{} = projected -> Map.put(expr, key, projected)
          _ -> expr
        end

      _ ->
        expr
    end
  end

  @spec parse_message_value(term(), term()) :: {:ok, term()} | :error
  defp parse_message_value(_message, %{} = message_value), do: {:ok, message_value}
  defp parse_message_value(message, _message_value), do: parse_message_value(message)

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

  @spec update_result_commands(term()) :: [map()]
  defp update_result_commands({_model, command}), do: flatten_runtime_commands(command)
  defp update_result_commands(_), do: []

  @spec flatten_runtime_commands(term()) :: [map()]
  defp flatten_runtime_commands(%{"kind" => "cmd.none"}), do: []
  defp flatten_runtime_commands(%{kind: "cmd.none"}), do: []

  defp flatten_runtime_commands(%{"kind" => "cmd.batch", "commands" => commands})
       when is_list(commands) do
    Enum.flat_map(commands, &flatten_runtime_commands/1)
  end

  defp flatten_runtime_commands(%{kind: "cmd.batch", commands: commands})
       when is_list(commands) do
    Enum.flat_map(commands, &flatten_runtime_commands/1)
  end

  defp flatten_runtime_commands(%{"kind" => "http"} = command), do: [command]
  defp flatten_runtime_commands(%{kind: "http"} = command), do: [stringify_command_keys(command)]
  defp flatten_runtime_commands(%{"kind" => "protocol"} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "protocol"} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(%{"kind" => "cmd.random.generate"} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.random.generate"} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(%{"kind" => "cmd.storage." <> _rest} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.storage." <> _rest} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(%{"kind" => "cmd.device." <> _rest} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.device." <> _rest} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(%{"kind" => "cmd.unsupported"} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.unsupported"} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(commands) when is_list(commands),
    do: Enum.flat_map(commands, &flatten_runtime_commands/1)

  defp flatten_runtime_commands(_), do: []

  @spec stringify_command_keys(map()) :: map()
  defp stringify_command_keys(command) when is_map(command) do
    Map.new(command, fn {key, value} -> {to_string(key), value} end)
  end

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
      |> normalize_runtime_text_fields()

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
  defp normalize_runtime_view_tree(value) do
    case normalize_pebble_ui_value(value) do
      {:ok, node} -> node
      :error -> normalize_runtime_view_tree_fallback(value)
    end
  end

  @spec normalize_runtime_view_tree_fallback(term()) :: term()
  defp normalize_runtime_view_tree_fallback(%{} = value) do
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

        node =
          if Map.has_key?(value, :text),
            do: Map.put(node, "text", to_string(value[:text])),
            else: node

        node =
          cond do
            is_map(Map.get(value, "style")) ->
              Map.put(node, "style", Map.get(value, "style"))

            is_map(Map.get(value, :style)) ->
              Map.put(node, "style", Map.get(value, :style))

            true ->
              node
          end

        promote_runtime_node_args(node)

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

  defp normalize_runtime_view_tree_fallback(list) when is_list(list) do
    %{
      "type" => "List",
      "label" => "[#{length(list)}]",
      "children" => Enum.map(list, &normalize_runtime_view_tree/1)
    }
  end

  defp normalize_runtime_view_tree_fallback({left, right}) do
    %{
      "type" => "tuple2",
      "label" => "",
      "children" => [normalize_runtime_view_tree(left), normalize_runtime_view_tree(right)]
    }
  end

  defp normalize_runtime_view_tree_fallback(value)
       when is_integer(value) or is_float(value) or is_boolean(value) or is_binary(value) do
    %{"type" => "expr", "label" => to_string(value), "value" => value, "children" => []}
  end

  defp normalize_runtime_view_tree_fallback(_),
    do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec normalize_runtime_text_fields(term()) :: term()
  defp normalize_runtime_text_fields(%{} = node) do
    node
    |> normalize_runtime_text_field("text")
    |> normalize_runtime_text_field(:text)
    |> normalize_runtime_children_text_fields()
  end

  defp normalize_runtime_text_fields(values) when is_list(values),
    do: Enum.map(values, &normalize_runtime_text_fields/1)

  defp normalize_runtime_text_fields(value), do: value

  @spec normalize_runtime_text_field(map(), term()) :: map()
  defp normalize_runtime_text_field(node, key) when is_map(node) do
    if Map.has_key?(node, key) do
      case normalize_text_value(Map.get(node, key)) do
        nil -> node
        text -> Map.put(node, key, text)
      end
    else
      node
    end
  end

  @spec normalize_runtime_children_text_fields(map()) :: map()
  defp normalize_runtime_children_text_fields(node) when is_map(node) do
    cond do
      is_list(Map.get(node, "children")) ->
        Map.update!(node, "children", &normalize_runtime_text_fields/1)

      is_list(Map.get(node, :children)) ->
        Map.update!(node, :children, &normalize_runtime_text_fields/1)

      true ->
        node
    end
  end

  @spec promote_runtime_node_args(map()) :: map()
  defp promote_runtime_node_args(%{"type" => "window", "children" => [id | rest]} = node) do
    case runtime_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_runtime_node_args(%{"type" => "canvasLayer", "children" => [id | rest]} = node) do
    case runtime_expr_scalar(id) do
      nil -> node
      value -> node |> Map.put("id", value) |> Map.put("children", rest)
    end
  end

  defp promote_runtime_node_args(%{"children" => children} = node) when is_list(children) do
    type = Map.get(node, "type")
    fields = runtime_node_arg_fields(type)

    if fields != [] and length(fields) == length(children) do
      values = Enum.map(children, &runtime_expr_scalar/1)

      if Enum.all?(values, &(!is_nil(&1))) do
        fields
        |> Enum.zip(values)
        |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
          put_runtime_node_arg(acc, field, value)
        end)
      else
        node
      end
    else
      node
    end
  end

  defp promote_runtime_node_args(node), do: node

  @spec put_runtime_node_arg(map(), String.t(), term()) :: map()
  defp put_runtime_node_arg(node, "text", value) when is_map(node) do
    Map.put(node, "text", normalize_text_value(value) || "")
  end

  defp put_runtime_node_arg(node, field, value) when is_map(node) do
    Map.put(node, field, value)
  end

  @spec runtime_expr_scalar(term()) :: term()
  defp runtime_expr_scalar(%{"type" => "expr"} = node) do
    cond do
      Map.has_key?(node, "value") -> Map.get(node, "value")
      is_binary(Map.get(node, "label")) -> Map.get(node, "label")
      true -> nil
    end
  end

  defp runtime_expr_scalar(%{type: "expr"} = node) do
    cond do
      Map.has_key?(node, :value) -> Map.get(node, :value)
      is_binary(Map.get(node, :label)) -> Map.get(node, :label)
      true -> nil
    end
  end

  defp runtime_expr_scalar(_node), do: nil

  @spec runtime_node_arg_fields(term()) :: [String.t()]
  defp runtime_node_arg_fields(type) do
    case to_string(type || "") do
      "clear" -> ["color"]
      "pixel" -> ["x", "y", "color"]
      "line" -> ["x1", "y1", "x2", "y2", "color"]
      "rect" -> ["x", "y", "w", "h", "color"]
      "fillRect" -> ["x", "y", "w", "h", "fill"]
      "circle" -> ["cx", "cy", "r", "color"]
      "fillCircle" -> ["cx", "cy", "r", "color"]
      "roundRect" -> ["x", "y", "w", "h", "radius", "fill"]
      "arc" -> ["x", "y", "w", "h", "start_angle", "end_angle"]
      "fillRadial" -> ["x", "y", "w", "h", "start_angle", "end_angle"]
      "bitmapInRect" -> ["bitmap_id", "x", "y", "w", "h"]
      "rotatedBitmap" -> ["bitmap_id", "src_w", "src_h", "angle", "center_x", "center_y"]
      "textInt" -> ["font_id", "x", "y", "value"]
      "textLabel" -> ["font_id", "x", "y", "text"]
      "text" -> ["font_id", "x", "y", "w", "h", "text"]
      _ -> []
    end
  end

  @spec normalize_pebble_ui_value(term()) :: {:ok, map()} | :error
  defp normalize_pebble_ui_value(%{"type" => type, "children" => children} = value)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(%{type: type, children: children} = value)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(value) do
    with {:ok, 1000, windows} <- tagged_constructor_value(value),
         {:ok, windows} <- constructor_list_values(windows),
         {:ok, window_nodes} <- normalize_pebble_ui_list(windows, &normalize_pebble_window_node/1) do
      {:ok, %{"type" => "windowStack", "label" => "", "children" => window_nodes}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_window_node(term()) :: {:ok, map()} | :error
  defp normalize_pebble_window_node(value) do
    with {:ok, 1001, payload} <- tagged_constructor_value(value),
         {:ok, [id, layers]} <- constructor_payload_args(payload, 2),
         {:ok, layers} <- constructor_list_values(layers),
         {:ok, layer_nodes} <- normalize_pebble_ui_list(layers, &normalize_pebble_layer_node/1) do
      {:ok,
       %{
         "type" => "window",
         "label" => "",
         "id" => runtime_expr_scalar(normalize_runtime_view_tree_fallback(id)),
         "children" => layer_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_layer_node(term()) :: {:ok, map()} | :error
  defp normalize_pebble_layer_node(value) do
    with {:ok, 1002, payload} <- tagged_constructor_value(value),
         {:ok, [id, ops]} <- constructor_payload_args(payload, 2),
         {:ok, ops} <- constructor_list_values(ops),
         {:ok, op_nodes} <- normalize_pebble_ui_list(ops, &normalize_pebble_render_op/1) do
      {:ok,
       %{
         "type" => "canvasLayer",
         "label" => "",
         "id" => runtime_expr_scalar(normalize_runtime_view_tree_fallback(id)),
         "children" => op_nodes
       }}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_render_op(term()) :: {:ok, map()} | :error
  defp normalize_pebble_render_op(value) do
    case normalize_pebble_context_group(value) do
      {:ok, node} -> {:ok, node}
      :error -> normalize_pebble_ui_value(value)
    end
  end

  @spec normalize_pebble_context_group(term()) :: {:ok, map()} | :error
  defp normalize_pebble_context_group(value) do
    with {:ok, 19, payload} <- tagged_constructor_value(value),
         {:ok, [settings, ops]} <- constructor_payload_args(payload, 2),
         {:ok, settings} <- constructor_list_values(settings),
         {:ok, ops} <- constructor_list_values(ops),
         style <- normalize_pebble_context_style(settings),
         {:ok, op_nodes} <- normalize_pebble_ui_list(ops, &normalize_pebble_render_op/1) do
      {:ok, %{"type" => "group", "label" => "", "style" => style, "children" => op_nodes}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_context_style([term()]) :: map()
  defp normalize_pebble_context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn setting, acc ->
      case normalize_pebble_context_setting(setting) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  @spec normalize_pebble_context_setting(term()) :: {String.t(), term()} | nil
  defp normalize_pebble_context_setting(setting) do
    with {:ok, tag, value} <- tagged_constructor_value(setting),
         key when is_binary(key) <- context_setting_key(tag) do
      {key, normalized_context_setting_value(value)}
    else
      _ -> nil
    end
  end

  @spec context_setting_key(term()) :: String.t() | nil
  defp context_setting_key(1), do: "stroke_width"
  defp context_setting_key(2), do: "antialiased"
  defp context_setting_key(3), do: "stroke_color"
  defp context_setting_key(4), do: "fill_color"
  defp context_setting_key(5), do: "text_color"
  defp context_setting_key(6), do: "compositing_mode"
  defp context_setting_key(_), do: nil

  @spec normalized_context_setting_value(term()) :: term()
  defp normalized_context_setting_value(value) when is_integer(value) or is_boolean(value),
    do: value

  defp normalized_context_setting_value(value),
    do: normalized_expr_value(normalize_runtime_view_tree_fallback(value))

  @spec normalize_pebble_ui_list([term()], (term() -> {:ok, map()} | :error)) ::
          {:ok, [map()]} | :error
  defp normalize_pebble_ui_list(values, fun) when is_list(values) and is_function(fun, 1) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, node} -> {:cont, {:ok, [node | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      :error -> :error
    end
  end

  @spec tagged_tuple(term()) :: {:ok, integer(), term()} | :error
  defp tagged_tuple({tag, payload}) when is_integer(tag), do: {:ok, tag, payload}
  defp tagged_tuple(_value), do: :error

  @spec tagged_constructor_value(term()) :: {:ok, integer(), term()} | :error
  defp tagged_constructor_value(value) do
    case tagged_tuple(value) do
      {:ok, tag, payload} ->
        {:ok, tag, payload}

      :error ->
        normalized_tagged_tuple(value)
    end
  end

  @spec normalized_tagged_tuple(term()) :: {:ok, integer(), term()} | :error
  defp normalized_tagged_tuple(%{"type" => "tuple2", "children" => [tag_node, payload]}) do
    case normalized_expr_value(tag_node) do
      tag when is_integer(tag) -> {:ok, tag, payload}
      _ -> :error
    end
  end

  defp normalized_tagged_tuple(%{type: "tuple2", children: [tag_node, payload]}) do
    case normalized_expr_value(tag_node) do
      tag when is_integer(tag) -> {:ok, tag, payload}
      _ -> :error
    end
  end

  defp normalized_tagged_tuple(_value), do: :error

  @spec normalized_expr_value(term()) :: term()
  defp normalized_expr_value(%{"type" => "expr"} = node), do: Map.get(node, "value")
  defp normalized_expr_value(%{type: "expr"} = node), do: Map.get(node, :value)
  defp normalized_expr_value(_node), do: nil

  @spec constructor_list_values(term()) :: {:ok, [term()]} | :error
  defp constructor_list_values(values) when is_list(values), do: {:ok, values}

  defp constructor_list_values(%{"type" => "List", "children" => children})
       when is_list(children),
       do: {:ok, children}

  defp constructor_list_values(%{type: "List", children: children}) when is_list(children),
    do: {:ok, children}

  defp constructor_list_values(_values), do: :error

  @spec constructor_payload_args(term(), non_neg_integer()) :: {:ok, [term()]} | :error
  defp constructor_payload_args(payload, 1), do: {:ok, [payload]}

  defp constructor_payload_args(payload, arity) when is_integer(arity) and arity > 1 do
    case flatten_constructor_payload(payload, arity, []) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  @spec flatten_constructor_payload(term(), non_neg_integer(), [term()]) ::
          {:ok, [term()]} | :error
  defp flatten_constructor_payload(value, 1, acc), do: {:ok, Enum.reverse([value | acc])}

  defp flatten_constructor_payload({left, right}, remaining, acc) when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(
         %{"type" => "tuple2", "children" => [left, right]},
         remaining,
         acc
       )
       when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(%{type: "tuple2", children: [left, right]}, remaining, acc)
       when remaining > 1 do
    flatten_constructor_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_constructor_payload(_value, _remaining, _acc), do: :error

  @spec evaluator_context(term()) :: term()
  defp evaluator_context(core_ir) do
    module_name = evaluator_entry_module(core_ir)

    %{
      module: module_name,
      source_module: module_name,
      functions: CoreIREvaluator.index_functions(core_ir),
      record_aliases: CoreIREvaluator.index_record_aliases(core_ir),
      record_alias_field_types: CoreIREvaluator.index_record_alias_field_types(core_ir),
      constructor_tags: CoreIREvaluator.index_constructor_tags(core_ir)
    }
  end

  @spec evaluator_entry_module(term()) :: String.t()
  defp evaluator_entry_module(core_ir) when is_map(core_ir) do
    modules = generic_map_value(core_ir, "modules")

    modules
    |> List.wrap()
    |> Enum.find_value(&module_name_with_decl(&1, "init"))
    |> case do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        modules
        |> List.wrap()
        |> Enum.find_value(&module_name/1)
        |> case do
          name when is_binary(name) and name != "" -> name
          _ -> "Main"
        end
    end
  end

  defp evaluator_entry_module(_core_ir), do: "Main"

  @spec module_name_with_decl(term(), String.t()) :: String.t() | nil
  defp module_name_with_decl(module, declaration_name) when is_map(module) do
    declarations = generic_map_value(module, "declarations") || []

    if Enum.any?(declarations, &(generic_map_value(&1, "name") == declaration_name)) do
      module_name(module)
    end
  end

  defp module_name_with_decl(_module, _declaration_name), do: nil

  @spec module_name(term()) :: String.t() | nil
  defp module_name(module) when is_map(module) do
    case generic_map_value(module, "name") do
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp module_name(_module), do: nil

  @spec normalize_runtime_model_by_declared_type(term(), term()) :: term()
  defp normalize_runtime_model_by_declared_type(runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    CoreIREvaluator.normalize_value_by_type(runtime_model, "Model", eval_context)
  end

  defp normalize_runtime_model_by_declared_type(runtime_model, _eval_context), do: runtime_model

  @spec enrich_runtime_model_for_view(term(), term()) :: term()
  defp enrich_runtime_model_for_view(runtime_model, current_model)
       when is_map(runtime_model) and is_map(current_model) do
    _current_model = current_model
    runtime_model
  end

  defp enrich_runtime_model_for_view(runtime_model, _current_model) when is_map(runtime_model),
    do: runtime_model

  defp enrich_runtime_model_for_view(_runtime_model, _current_model), do: %{}

  @spec source_core_ir_fallback(term(), term(), term()) :: term()
  defp source_core_ir_fallback(core_ir, _source, _rel_path) when is_map(core_ir), do: core_ir

  defp source_core_ir_fallback(_core_ir, source, rel_path)
       when is_binary(source) and byte_size(source) > 0 do
    path =
      case rel_path do
        value when is_binary(value) and value != "" -> value
        _ -> "Main.elm"
      end

    with {:ok, module} <- GeneratedParser.parse_source(path, source),
         project <- %Project{
           project_dir: path |> Path.dirname() |> Path.expand(),
           elm_json: %{},
           modules: [module],
           diagnostics: []
         },
         {:ok, ir} <- Lowerer.lower_project(project),
         {:ok, core_ir} <- CoreIR.from_ir(ir) do
      core_ir
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp source_core_ir_fallback(_core_ir, _source, _rel_path), do: nil

  @spec normalize_launch_context(term()) :: map()
  defp normalize_launch_context(context) when is_map(context) do
    reason =
      case map_value(context, :reason) do
        %{"ctor" => _} = value -> value
        %{ctor: _} = value -> value
        value when is_binary(value) -> %{"ctor" => value, "args" => []}
        _ -> launch_reason_value(map_value(context, :launch_reason))
      end

    screen =
      case map_value(context, :screen) do
        value when is_map(value) ->
          %{
            "width" => map_value(value, :width) || map_value(context, :screenW) || 144,
            "height" => map_value(value, :height) || map_value(context, :screenH) || 168,
            "isColor" => map_value(value, :is_color) || map_value(value, :isColor) || true,
            "isRound" => map_value(value, :is_round) || map_value(value, :isRound) || false
          }

        _ ->
          %{
            "width" => map_value(context, :screenW) || 144,
            "height" => map_value(context, :screenH) || 168,
            "isColor" => map_value(context, :is_color) || true,
            "isRound" => map_value(context, :is_round) || false
          }
      end

    context
    |> Map.put("reason", reason)
    |> Map.put(
      "watchModel",
      map_value(context, :watch_model) || map_value(context, :watchModel) || "Basalt"
    )
    |> Map.put(
      "watchProfileId",
      map_value(context, :watch_profile_id) || map_value(context, :watchProfileId) || "basalt"
    )
    |> Map.put("screen", screen)
  end

  defp normalize_launch_context(_context) do
    normalize_launch_context(%{})
  end

  @spec launch_reason_value(term()) :: map()
  defp launch_reason_value(value) when is_binary(value) and value != "",
    do: %{"ctor" => value, "args" => []}

  defp launch_reason_value(_value), do: %{"ctor" => "LaunchUser", "args" => []}

  @spec derive_view_output(term(), term(), term()) :: term()
  defp derive_view_output(view_tree, runtime_model, eval_context)
       when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    view_output_from_tree(view_tree, runtime_model, eval_context)
  end

  defp derive_view_output(_view_tree, _runtime_model, _eval_context), do: []

  @spec view_output_from_tree(term(), term(), term()) :: term()
  defp view_output_from_tree(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type =
      node
      |> Map.get("type", Map.get(node, :type, ""))
      |> to_string()

    children =
      case Map.get(node, "children") || Map.get(node, :children) do
        list when is_list(list) -> list
        _ -> []
      end

    case type do
      "group" ->
        style_rows = view_output_style_rows(node)

        child_rows =
          Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))

        if style_rows == [] do
          child_rows
        else
          [%{"kind" => "push_context"}] ++
            style_rows ++ child_rows ++ [%{"kind" => "pop_context"}]
        end

      type when type in ["root", "windowStack", "window", "canvasLayer", "List"] ->
        Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))

      _ ->
        view_output_from_node(node, runtime_model, eval_context)
    end
  end

  defp view_output_from_tree(_node, _runtime_model, _eval_context), do: []

  @spec view_output_style_rows(term()) :: [map()]
  defp view_output_style_rows(node) when is_map(node) do
    style = Map.get(node, "style") || Map.get(node, :style) || %{}

    if is_map(style) do
      [
        style_row(style, "stroke_width", "stroke_width", "value"),
        style_row(style, "antialiased", "antialiased", "value"),
        style_row(style, "stroke_color", "stroke_color", "color"),
        style_row(style, "fill_color", "fill_color", "color"),
        style_row(style, "text_color", "text_color", "color"),
        style_row(style, "compositing_mode", "compositing_mode", "value")
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp view_output_style_rows(_node), do: []

  @spec style_row(map(), String.t(), String.t(), String.t()) :: map() | nil
  defp style_row(style, source_key, kind, value_key)
       when is_map(style) and is_binary(source_key) and is_binary(kind) and is_binary(value_key) do
    case style_value(style, source_key) do
      nil -> nil
      value -> %{"kind" => kind, value_key => value}
    end
  end

  @spec style_value(map(), String.t()) :: term()
  defp style_value(style, key) when is_map(style) and is_binary(key) do
    case Map.fetch(style, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(style, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: value, else: nil

          _ ->
            nil
        end)
    end
  end

  @spec view_output_from_node(term(), term(), term()) :: term()
  defp view_output_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type =
      node
      |> Map.get("type", Map.get(node, :type, ""))
      |> to_string()

    ints = node_int_args(node, runtime_model, eval_context)

    rows =
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

    Enum.map(rows, &put_view_output_source(&1, node))
  end

  defp view_output_from_node(_node, _runtime_model, _eval_context), do: []

  @spec put_view_output_source(term(), term()) :: term()
  defp put_view_output_source(row, node) when is_map(row) and is_map(node) do
    case Map.get(node, "source") || Map.get(node, :source) do
      %{} = source -> Map.put(row, "source", source)
      _ -> row
    end
  end

  defp put_view_output_source(row, _node), do: row

  @spec annotate_view_output_sources([term()], map()) :: [term()]
  defp annotate_view_output_sources(rows, introspect) when is_list(rows) and is_map(introspect) do
    source_locations =
      map_value(introspect, :view_source_locations)
      |> case do
        %{} = value -> value
        _ -> %{}
      end

    {annotated, _counters} =
      Enum.map_reduce(rows, %{}, fn row, counters ->
        kind = if is_map(row), do: to_string(map_value(row, :kind) || "")

        cond do
          not is_map(row) ->
            {row, counters}

          map_value(row, :source) != nil ->
            {row, increment_view_output_counter(counters, kind)}

          kind == "" ->
            {row, counters}

          true ->
            index = Map.get(counters, kind, 0)

            source =
              source_locations
              |> Map.get(kind)
              |> source_location_at(index)

            row =
              case source do
                %{} = source -> Map.put(row, "source", source)
                _ -> row
              end

            {row, increment_view_output_counter(counters, kind)}
        end
      end)

    annotated
  end

  defp annotate_view_output_sources(rows, _introspect) when is_list(rows), do: rows

  @spec increment_view_output_counter(map(), String.t() | nil) :: map()
  defp increment_view_output_counter(counters, kind)
       when is_map(counters) and is_binary(kind) and kind != "" do
    Map.update(counters, kind, 1, &(&1 + 1))
  end

  defp increment_view_output_counter(counters, _kind), do: counters

  @spec source_location_at(term(), non_neg_integer()) :: map() | nil
  defp source_location_at(locations, index) when is_list(locations) and locations != [] do
    Enum.at(locations, index) || List.last(locations)
  end

  defp source_location_at(_locations, _index), do: nil

  @spec node_int_args(term(), term(), term()) :: term()
  defp node_int_args(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    label = (node["label"] || node[:label] || "") |> to_string()
    from_label = extract_ints(label)
    from_fields = node_int_args_from_fields(node)
    min_arity = min_int_arity_for_node(node)

    cond do
      from_fields != [] and length(from_fields) >= min_arity ->
        from_fields

      from_label != [] and length(from_label) >= min_arity ->
        from_label

      true ->
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

  @spec node_int_args_from_fields(map()) :: [integer()]
  defp node_int_args_from_fields(node) when is_map(node) do
    node
    |> Map.get("type", Map.get(node, :type))
    |> runtime_node_arg_fields()
    |> Enum.map(fn field -> Map.get(node, field) || Map.get(node, String.to_atom(field)) end)
    |> Enum.filter(&is_integer/1)
  end

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

  defp normalize_text_value(value) when is_list(value) do
    if List.ascii_printable?(value) do
      value
      |> List.to_string()
      |> normalize_text_value()
    else
      nil
    end
  end

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
  defp eval_int_call("__pow__", [a, b]) when b >= 0, do: round(:math.pow(a, b))
  defp eval_int_call("__fdiv__", [_a, 0]), do: nil
  defp eval_int_call("__fdiv__", [a, b]), do: trunc(a / b)
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

  defp eval_int_call("remainderBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

  defp eval_int_call("Basics.remainderBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

  defp eval_int_call("basics.remainderby", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

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
    field_text = Map.get(node, "text") || Map.get(node, :text)

    child_text =
      case node_children(node) do
        [_font_node, _pos_node, label_node | _] ->
          eval_view_text(label_node, runtime_model, eval_context)

        _ ->
          nil
      end

    cond do
      is_binary(field_text) and String.trim(field_text) != "" ->
        field_text

      is_binary(child_text) and String.trim(child_text) != "" ->
        child_text

      true ->
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
        field_text = Map.get(node, "text") || Map.get(node, :text)

        if text = normalize_text_value(field_text) do
          {:ok, [font_id, x, y, w, h, text]}
        else
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

  @spec protocol_events(term(), term()) :: term()
  defp protocol_events(_source_root, commands) when is_list(commands) do
    commands
    |> Enum.filter(&protocol_command?/1)
    |> Enum.flat_map(&protocol_command_events/1)
  end

  defp protocol_events(_source_root, _commands), do: []

  @spec protocol_command?(term()) :: boolean()
  defp protocol_command?(%{"kind" => "protocol"}), do: true
  defp protocol_command?(%{kind: "protocol"}), do: true
  defp protocol_command?(_), do: false

  @spec protocol_command_events(map()) :: [map()]
  defp protocol_command_events(command) when is_map(command) do
    from = map_value(command, :from) || "companion"
    to = map_value(command, :to) || "watch"
    message = map_value(command, :message)
    message_value = map_value(command, :message_value)

    if is_binary(message) and message != "" do
      payload = %{
        from: from,
        to: to,
        message: message,
        message_value: message_value,
        trigger: "runtime_cmd",
        message_source: "runtime_cmd"
      }

      [
        %{type: "debugger.protocol_tx", payload: payload},
        %{type: "debugger.protocol_rx", payload: payload}
      ]
    else
      []
    end
  end

  @spec package_followup_messages(term(), term()) :: [map()]
  defp package_followup_messages(commands, source_root)
       when is_list(commands) and is_binary(source_root) do
    commands
    |> Enum.flat_map(fn command ->
      cond do
        http_command?(command) ->
          [
            %{
              "message" => http_command_display(command),
              "source_root" => source_root,
              "source" => "http_command",
              "package" => "elm/http",
              "command" => command
            }
          ]

        random_command?(command) ->
          [
            %{
              "message" => map_value(command, :message) || "RandomGenerated",
              "message_value" => map_value(command, :message_value),
              "source_root" => source_root,
              "source" => "random_command",
              "package" => "elm/random",
              "command" => command
            }
          ]

        storage_read_command?(command) ->
          [
            %{
              "message" => map_value(command, :message) || "StorageLoaded",
              "message_value" => map_value(command, :message_value),
              "source_root" => source_root,
              "source" => "storage_command",
              "package" => "elm-pebble/elm-watch",
              "command" => command
            }
          ]

        storage_write_command?(command) or storage_delete_command?(command) ->
          [
            %{
              "message" => nil,
              "source_root" => source_root,
              "source" => "storage_command",
              "package" => "elm-pebble/elm-watch",
              "command" => command
            }
          ]

        device_command?(command) ->
          [
            %{
              "message" => map_value(command, :message) || "DeviceLoaded",
              "message_value" => map_value(command, :message_value),
              "source_root" => source_root,
              "source" => "device_command",
              "package" => "elm-pebble/elm-watch",
              "command" => command
            }
          ]

        unsupported_command?(command) ->
          [
            %{
              "message" => "Unsupported command",
              "source_root" => source_root,
              "source" => "unsupported_command",
              "package" => map_value(command, :package) || "unknown",
              "command" => command
            }
          ]

        true ->
          []
      end
    end)
  end

  defp package_followup_messages(_commands, _source_root), do: []

  @spec http_command?(term()) :: boolean()
  defp http_command?(%{"kind" => "http"}), do: true
  defp http_command?(%{kind: "http"}), do: true
  defp http_command?(_), do: false

  @spec random_command?(term()) :: boolean()
  defp random_command?(%{"kind" => "cmd.random.generate"}), do: true
  defp random_command?(%{kind: "cmd.random.generate"}), do: true
  defp random_command?(_), do: false

  @spec storage_read_command?(term()) :: boolean()
  defp storage_read_command?(%{"kind" => "cmd.storage.read_" <> _rest}), do: true
  defp storage_read_command?(%{kind: "cmd.storage.read_" <> _rest}), do: true
  defp storage_read_command?(_), do: false

  @spec storage_write_command?(term()) :: boolean()
  defp storage_write_command?(%{"kind" => "cmd.storage.write_" <> _rest}), do: true
  defp storage_write_command?(%{kind: "cmd.storage.write_" <> _rest}), do: true
  defp storage_write_command?(_), do: false

  @spec storage_delete_command?(term()) :: boolean()
  defp storage_delete_command?(%{"kind" => "cmd.storage.delete"}), do: true
  defp storage_delete_command?(%{kind: "cmd.storage.delete"}), do: true
  defp storage_delete_command?(_), do: false

  @spec device_command?(term()) :: boolean()
  defp device_command?(%{"kind" => "cmd.device." <> _rest}), do: true
  defp device_command?(%{kind: "cmd.device." <> _rest}), do: true
  defp device_command?(_), do: false

  @spec unsupported_command?(term()) :: boolean()
  defp unsupported_command?(%{"kind" => "cmd.unsupported"}), do: true
  defp unsupported_command?(%{kind: "cmd.unsupported"}), do: true
  defp unsupported_command?(_), do: false

  @spec http_command_display(term()) :: String.t()
  defp http_command_display(command) when is_map(command) do
    expect = map_value(command, :expect)
    to_msg = if is_map(expect), do: map_value(expect, :to_msg), else: nil
    callback = callable_display_name(to_msg)
    method = map_value(command, :method) || "GET"
    url = map_value(command, :url) || ""

    if callback == "" do
      "#{method} #{url}"
    else
      "#{callback} <#{method} #{url}>"
    end
  end

  defp http_command_display(_), do: "elm/http"

  @spec callable_display_name(term()) :: String.t()
  defp callable_display_name({:function_ref, name}) when is_binary(name),
    do: unqualified_identifier(name)

  defp callable_display_name(name) when is_binary(name), do: unqualified_identifier(name)
  defp callable_display_name(_), do: ""

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
