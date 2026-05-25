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
  alias ElmExecutor.Runtime.CoreIRContract
  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

  @doc """
  Evaluates a parser-derived rendered view node against the current runtime model.

  This is used by debugger UI code to annotate the source-shaped rendered hierarchy
  with the same values the semantic executor can derive for visual preview output.
  """
  @spec evaluate_view_tree_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
  def evaluate_view_tree_value(node, runtime_model, eval_context \\ %{})

  def evaluate_view_tree_value(node, runtime_model, eval_context)
      when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    eval_tree_expr_value(node, runtime_model, eval_context)
  end

  def evaluate_view_tree_value(_node, _runtime_model, _eval_context), do: nil

  @doc """
  Derives drawable preview rows from a parser-shaped view tree and runtime model.

  Used when full Core IR view evaluation is unavailable but the introspected view
  tree still contains render-operation structure.
  """
  @spec derive_view_output_preview(map(), map(), map()) :: [map()]
  def derive_view_output_preview(view_tree, runtime_model, eval_context \\ %{})

  def derive_view_output_preview(view_tree, runtime_model, eval_context)
      when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    eval_context = Map.put(eval_context, :runtime_model, runtime_model)

    view_tree
    |> derive_view_output(runtime_model, eval_context)
    |> Enum.map(&stringify_view_output_row/1)
  end

  def derive_view_output_preview(_view_tree, _runtime_model, _eval_context), do: []

  @spec stringify_view_output_row(map()) :: map()
  defp stringify_view_output_row(row) when is_map(row) do
    Map.new(row, fn {key, value} -> {to_string(key), value} end)
  end

  @spec execute(SemTypes.execution_request() | map()) ::
          {:ok, SemTypes.execution_result()} | {:error, SemTypes.exec_error()}
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

    with :ok <- CoreIRContract.validate(core_ir) do
      execute_validated(request, core_ir, %{
        source_root: source_root,
        rel_path: rel_path,
        source: source,
        introspect: introspect,
        source_module: map_value(introspect, :module),
        current_model: current_model,
        current_view_tree: current_view_tree,
        message: message,
        message_value: message_value
      })
    end
  end

  def execute(_), do: {:error, :invalid_execution_request}

  defp execute_validated(request, core_ir, ctx) do
    %{
      source_root: source_root,
      rel_path: rel_path,
      source: source,
      introspect: introspect,
      source_module: source_module,
      current_model: current_model,
      current_view_tree: current_view_tree,
      message: message,
      message_value: message_value
    } = ctx

    eval_context =
      core_ir
      |> evaluator_context(source_module)
      |> Map.merge(vector_resource_indices_context(request, current_model))
      |> Map.merge(bitmap_resource_indices_context(request, current_model))
      |> Map.put(:launch_context, launch_context_from_model(current_model))
    static_init_model = map_value(introspect, :init_model)

    base_runtime_model =
      case map_value(current_model, :runtime_model) do
        model when is_map(model) and map_size(model) > 0 ->
          if unresolved_runtime_model?(model) do
            evaluated_init_model(core_ir, eval_context, current_model) || model
          else
            model
          end

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
                 core_ir,
                 eval_context,
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

    followup_messages =
      runtime_commands
      |> package_followup_messages(source_root)
      |> resolve_timer_followup_messages(eval_context)

    eval_context = Map.put(eval_context, :runtime_model, runtime_model_for_view)

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

  @spec map_value(map(), atom() | String.t()) :: EvalTypes.runtime_value() | nil
  defp map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  @spec generic_map_value(map(), String.t()) :: EvalTypes.runtime_value() | nil
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

  @spec meaningful_init_cmd_count(map()) :: non_neg_integer()
  defp meaningful_init_cmd_count(introspect) do
    introspect
    |> map_value(:init_cmd_calls)
    |> case do
      calls when is_list(calls) -> calls
      _ -> []
    end
    |> Enum.count(&meaningful_init_cmd_call?/1)
  end

  @spec meaningful_init_cmd_call?(SemTypes.command_map()) :: boolean()
  defp meaningful_init_cmd_call?(call) when is_map(call) do
    target = map_value(call, :target)
    name = map_value(call, :name)
    not (target in ["Cmd.none", "Platform.Cmd.none"] or name in ["none", "None", nil])
  end

  defp meaningful_init_cmd_call?(_call), do: false

  @spec evaluate_update_from_core_ir(map(), map(), String.t(), SemTypes.message_value(), map()) ::
          {:ok, map(), [map()], atom() | nil, String.t(), map()} | :error
  defp evaluate_update_from_core_ir(core_ir, eval_context, message, message_value, runtime_model)
       when is_map(eval_context) and is_binary(message) and is_map(runtime_model) do
    with %{} = update_expr <- update_function_expr_from_core_ir(core_ir),
         {:ok, msg_value} <- parse_message_value(message, message_value),
         msg_value = normalize_msg_for_core_ir(msg_value, eval_context),
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

  @spec evaluated_init_model_if_static_unresolved(map(), map(), map(), map() | nil) :: map() | nil
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

  @spec unresolved_runtime_model?(map()) :: boolean()
  defp unresolved_runtime_model?(model) when is_map(model) do
    Enum.any?(model, fn {_key, value} -> unresolved_runtime_value?(value) end)
  end

  defp unresolved_runtime_model?(_model), do: false

  @spec update_function_expr_from_core_ir(map()) :: map() | nil
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

  @spec entry_module_name(map()) :: String.t()
  defp entry_module_name(eval_context) when is_map(eval_context) do
    Map.get(eval_context, :module) || Map.get(eval_context, "module") || "Main"
  end

  @spec init_call_candidates(String.t(), map()) :: [map()]
  defp init_call_candidates(entry_module, launch_context) when is_binary(entry_module) do
    [
      %{"op" => :qualified_call, "target" => "#{entry_module}.init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "#{entry_module}.init", "args" => [%{}]},
      %{"op" => :qualified_call, "target" => "#{entry_module}.init", "args" => []},
      %{"op" => :qualified_call, "target" => "Main.init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "init", "args" => [launch_context]},
      %{"op" => :qualified_call, "target" => "Main.init", "args" => []},
      %{"op" => :qualified_call, "target" => "init", "args" => []}
    ]
  end

  @spec evaluated_init_model(map(), map(), map()) :: map() | nil
  defp evaluated_init_model(_core_ir, eval_context, current_model)
       when is_map(eval_context) and is_map(current_model) do
    launch_context = current_model |> map_value(:launch_context) |> normalize_launch_context()
    entry_module = entry_module_name(eval_context)

    candidates = init_call_candidates(entry_module, launch_context)

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

  @spec evaluated_init_model_from_projected_expr(map(), SemTypes.launch_context()) :: map() | nil
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

  @spec init_runtime_commands(map(), map()) :: [SemTypes.command_map()]
  defp init_runtime_commands(eval_context, current_model)
       when is_map(eval_context) and is_map(current_model) do
    launch_context = current_model |> map_value(:launch_context) |> normalize_launch_context()
    entry_module = entry_module_name(eval_context)

    init_call_candidates(entry_module, launch_context)
    |> Enum.find_value(fn expr ->
      with {:ok, result} <- CoreIREvaluator.evaluate(expr, %{}, eval_context),
           cmds when cmds != [] <- update_result_commands(result) do
        cmds
      else
        _ -> nil
      end
    end) || init_runtime_commands_from_projected_expr(eval_context, launch_context)
  end

  defp init_runtime_commands(_eval_context, _current_model), do: []

  @spec init_runtime_commands_from_projected_expr(map(), SemTypes.launch_context()) :: [SemTypes.command_map()]
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

  @spec project_cmd_result_expr(map()) :: map() | nil
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

  @spec evaluate_model_command_result(map(), map(), map()) :: EvalTypes.eval_result()
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

  @spec function_defs_named(map(), String.t()) :: [map()]
  defp function_defs_named(eval_context, name) when is_map(eval_context) and is_binary(name) do
    eval_context
    |> Map.get(:functions, %{})
    |> Map.values()
    |> Enum.filter(&(Map.get(&1, :name) == name))
    |> Enum.sort_by(&(length(Map.get(&1, :params, [])) != 1))
  end

  @spec project_model_result_expr(map()) :: map() | nil
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

  @spec parse_message_value(String.t(), SemTypes.message_value()) :: {:ok, SemTypes.message_value()} | :error
  defp parse_message_value(_message, %{} = message_value),
    do: {:ok, normalize_wire_message_value(message_value)}

  defp parse_message_value(_message, {tag, _payload} = message_value) when is_integer(tag),
    do: {:ok, message_value}

  defp parse_message_value(message, _message_value), do: parse_message_value(message)

  @spec normalize_wire_message_value(SemTypes.message_value()) :: SemTypes.message_value()
  defp normalize_wire_message_value(%{"ctor" => "Ok", "args" => [inner | _]}) do
    {1, normalize_wire_message_value(inner)}
  end

  defp normalize_wire_message_value(%{"ctor" => "Err", "args" => [inner | _]}) do
    {0, normalize_wire_message_value(inner)}
  end

  defp normalize_wire_message_value(%{ctor: "Ok", args: [inner | _]}) do
    {1, normalize_wire_message_value(inner)}
  end

  defp normalize_wire_message_value(%{ctor: "Err", args: [inner | _]}) do
    {0, normalize_wire_message_value(inner)}
  end

  defp normalize_wire_message_value(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args) do
    %{"ctor" => ctor, "args" => Enum.map(args, &normalize_wire_message_value/1)}
  end

  defp normalize_wire_message_value(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args) do
    %{"ctor" => ctor, "args" => Enum.map(args, &normalize_wire_message_value/1)}
  end

  defp normalize_wire_message_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, normalize_wire_message_value(nested)} end)
  end

  defp normalize_wire_message_value(value) when is_list(value),
    do: Enum.map(value, &normalize_wire_message_value/1)

  defp normalize_wire_message_value(value), do: value

  @spec normalize_msg_for_core_ir(SemTypes.message_value(), map()) :: SemTypes.message_value()
  defp normalize_msg_for_core_ir(%{"ctor" => ctor, "args" => args}, eval_context)
       when is_binary(ctor) and is_list(args) do
    %{
      "ctor" => ctor,
      "args" => Enum.map(args, &normalize_msg_ctor_arg(&1, eval_context))
    }
  end

  defp normalize_msg_for_core_ir(%{ctor: ctor, args: args}, eval_context)
       when is_binary(ctor) and is_list(args) do
    normalize_msg_for_core_ir(%{"ctor" => ctor, "args" => args}, eval_context)
  end

  defp normalize_msg_for_core_ir({tag, args}, eval_context) when is_integer(tag) and is_list(args) do
    {tag, Enum.map(args, &normalize_msg_ctor_arg(&1, eval_context))}
  end

  defp normalize_msg_for_core_ir(value, _eval_context), do: normalize_wire_message_value(value)

  @spec normalize_msg_ctor_arg(SemTypes.message_value(), map()) :: SemTypes.message_value()
  defp normalize_msg_ctor_arg(%{"ctor" => ctor, "args" => args}, _eval_context)
       when is_binary(ctor) and is_list(args) do
    %{"ctor" => ctor, "args" => Enum.map(args, &normalize_wire_message_value/1)}
  end

  defp normalize_msg_ctor_arg(%{ctor: ctor, args: args}, eval_context)
       when is_binary(ctor) and is_list(args) do
    normalize_msg_ctor_arg(%{"ctor" => ctor, "args" => args}, eval_context)
  end

  defp normalize_msg_ctor_arg(value, _eval_context), do: normalize_wire_message_value(value)

  @spec parse_message_value(String.t()) :: {:ok, map()} | :error
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

  @spec parse_message_arguments(String.t(), [String.t()]) :: [String.t()]
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

  @spec parse_message_argument_value(String.t()) :: SemTypes.message_value()
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

  @spec parse_constructor_message_argument(String.t()) :: SemTypes.message_value()
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

  @spec parse_numeric_message_argument(String.t()) :: EvalTypes.runtime_value()
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

  @spec update_result_model(EvalTypes.runtime_value() | map() | tuple()) :: {:ok, map()} | :error
  defp update_result_model({left, _right}) when is_map(left), do: {:ok, left}
  defp update_result_model(model) when is_map(model), do: {:ok, model}
  defp update_result_model(_), do: :error

  @spec update_result_commands(EvalTypes.runtime_value() | tuple()) :: [SemTypes.command_map()]
  defp update_result_commands({_model, command}), do: flatten_runtime_commands(command)
  defp update_result_commands(_), do: []

  @spec flatten_runtime_commands(EvalTypes.runtime_value()) :: [SemTypes.command_map()]
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

  defp flatten_runtime_commands(%{"kind" => "cmd.task." <> _rest} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.task." <> _rest} = command),
    do: [stringify_command_keys(command)]

  defp flatten_runtime_commands(%{"kind" => "cmd.timer.after"} = command), do: [command]

  defp flatten_runtime_commands(%{kind: "cmd.timer.after"} = command),
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

  @spec take_single_argument(String.t()) :: {String.t(), String.t()}
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

  @spec take_group_argument(String.t()) :: {String.t(), String.t()}
  defp take_group_argument(<<open, rest::binary>>) when open in [?(, ?[, ?{] do
    closer = matching_closer(open)
    consume_group(rest, [closer], <<open>>)
  end

  @spec consume_group(String.t(), [integer()], String.t()) :: {String.t(), String.t()}
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

  @spec matching_closer(integer()) :: integer() | nil
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

  @spec derive_view_tree(map(), map(), map(), String.t(), String.t() | nil, atom() | nil, map()) :: map()
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

  @spec evaluate_runtime_view_tree(map(), map()) :: map()
  defp evaluate_runtime_view_tree(eval_context, runtime_model)
       when is_map(eval_context) and is_map(runtime_model) do
    entry_module = entry_module_name(eval_context)
    expr = %{"op" => :qualified_call, "target" => "#{entry_module}.view", "args" => [runtime_model]}

    case CoreIREvaluator.evaluate(expr, %{"model" => runtime_model}, eval_context) do
      {:ok, value} ->
        normalize_runtime_view_tree(value, eval_context)

      _ ->
        %{}
    end
  end

  defp evaluate_runtime_view_tree(_eval_context, _runtime_model), do: %{}

  @spec normalize_runtime_view_tree(EvalTypes.runtime_value(), map()) :: map()
  defp normalize_runtime_view_tree(value, eval_context \\ %{}) do
    case normalize_pebble_ui_value(value, eval_context) do
      {:ok, node} -> node
      :error -> normalize_runtime_view_tree_fallback(value)
    end
  end

  @spec normalize_runtime_view_tree_fallback(EvalTypes.runtime_value()) :: map()
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

  @spec normalize_runtime_text_fields(map() | list() | term()) :: map() | list() | term()
  defp normalize_runtime_text_fields(%{} = node) do
    node
    |> normalize_runtime_text_field("text")
    |> normalize_runtime_text_field(:text)
    |> normalize_runtime_children_text_fields()
  end

  defp normalize_runtime_text_fields(values) when is_list(values),
    do: Enum.map(values, &normalize_runtime_text_fields/1)

  defp normalize_runtime_text_fields(value), do: value

  @spec normalize_runtime_text_field(map(), String.t() | atom()) :: map()
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

  defp promote_runtime_node_args(%{"type" => "text", "children" => children} = node)
       when is_list(children) and length(children) == 6 do
    values = Enum.map(children, &runtime_expr_scalar/1)

    if Enum.all?(values, &(!is_nil(&1))) do
      ["font_id", "x", "y", "w", "h", "text"]
      |> Enum.zip(values)
      |> Enum.reduce(Map.put(node, "children", []), fn {field, value}, acc ->
        put_runtime_node_arg(acc, field, value)
      end)
      |> Map.put("text_align", "center")
      |> Map.put("text_overflow", "word_wrap")
    else
      node
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

  @spec put_runtime_node_arg(map(), String.t(), EvalTypes.runtime_value()) :: map()
  defp put_runtime_node_arg(node, "text", value) when is_map(node) do
    Map.put(node, "text", normalize_text_value(value) || "")
  end

  defp put_runtime_node_arg(node, "text_align", value) when is_map(node) do
    Map.put(node, "text_align", text_alignment_name(value))
  end

  defp put_runtime_node_arg(node, "text_overflow", value) when is_map(node) do
    Map.put(node, "text_overflow", text_overflow_name(value))
  end

  defp put_runtime_node_arg(node, field, value) when is_map(node) do
    Map.put(node, field, value)
  end

  @spec runtime_expr_scalar(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
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

  @spec runtime_node_arg_fields(String.t() | atom()) :: [String.t()]
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
      "drawVectorAt" -> ["vector_id", "x", "y"]
      "vectorAt" -> ["vector_id", "x", "y"]
      "drawVectorSequenceAt" -> ["vector_id", "x", "y"]
      "vectorSequenceAt" -> ["vector_id", "x", "y"]
      "textInt" -> ["font_id", "x", "y", "value"]
      "textLabel" -> ["font_id", "x", "y", "text"]
      "text" -> ["font_id", "x", "y", "w", "h", "text_align", "text_overflow", "text"]
      _ -> []
    end
  end

  @spec normalize_pebble_ui_value(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_ui_value(%{"type" => type, "children" => children} = value, _eval_context)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(%{type: type, children: children} = value, _eval_context)
       when is_binary(type) and is_list(children) and type not in ["tuple2", "List"] do
    {:ok, normalize_runtime_view_tree_fallback(value)}
  end

  defp normalize_pebble_ui_value(value, eval_context) do
    with {:ok, 1000, windows} <- tagged_constructor_value(value),
         {:ok, windows} <- constructor_list_values(windows),
         {:ok, window_nodes} <-
           normalize_pebble_ui_list(windows, &normalize_pebble_window_node(&1, eval_context)) do
      {:ok, %{"type" => "windowStack", "label" => "", "children" => window_nodes}}
    else
      _ ->
        case normalize_pebble_render_ops_list(value, eval_context) do
          {:ok, node} -> {:ok, node}
          :error -> :error
        end
    end
  end

  @spec normalize_pebble_render_ops_list(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_render_ops_list(value, eval_context) do
    with {:ok, ops} <- constructor_list_values(value),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)),
         true <- op_nodes != [] do
      canvas = %{
        "type" => "canvasLayer",
        "label" => "",
        "id" => 1,
        "children" => op_nodes
      }

      window = %{
        "type" => "window",
        "label" => "",
        "id" => 1,
        "children" => [canvas]
      }

      {:ok, %{"type" => "windowStack", "label" => "", "children" => [window]}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_window_node(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_window_node(value, eval_context) do
    with {:ok, 1001, payload} <- tagged_constructor_value(value),
         {:ok, [id, layers]} <- constructor_payload_args(payload, 2),
         {:ok, layers} <- constructor_list_values(layers),
         {:ok, layer_nodes} <-
           normalize_pebble_ui_list(layers, &normalize_pebble_layer_node(&1, eval_context)) do
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

  @spec normalize_pebble_layer_node(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_layer_node(value, eval_context) do
    with {:ok, 1002, payload} <- tagged_constructor_value(value),
         {:ok, [id, ops]} <- constructor_payload_args(payload, 2),
         {:ok, ops} <- constructor_list_values(ops),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)) do
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

  @spec normalize_pebble_render_op(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_render_op(value, eval_context) do
    case normalize_pebble_context_group(value, eval_context) do
      {:ok, node} ->
        {:ok, node}

      :error ->
        case normalize_pebble_tagged_render_op(value, eval_context) do
          {:ok, node} -> {:ok, node}
          :error -> normalize_pebble_ui_value(value, eval_context)
        end
    end
  end

  @spec normalize_pebble_tagged_render_op(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_tagged_render_op(value, eval_context) when is_map(eval_context) do
    with {:ok, tag, payload} <- tagged_constructor_value(value),
         type when is_binary(type) <- render_op_type_for_tag(tag),
         {:ok, args} <- render_op_args_for_tag(tag, payload),
         {:ok, fields} <- normalize_render_op_fields(type, args, eval_context) do
      {:ok,
       %{
         "type" => type,
         "label" => "",
         "children" => Enum.map(fields, &normalize_runtime_view_tree_fallback/1)
       }}
    else
      _ -> :error
    end
  end

  defp normalize_pebble_tagged_render_op(_value, _eval_context), do: :error

  @spec render_op_type_for_tag(integer()) :: String.t() | nil
  defp render_op_type_for_tag(1), do: "textInt"
  defp render_op_type_for_tag(2), do: "textLabel"
  defp render_op_type_for_tag(3), do: "text"
  defp render_op_type_for_tag(4), do: "clear"
  defp render_op_type_for_tag(5), do: "pixel"
  defp render_op_type_for_tag(6), do: "line"
  defp render_op_type_for_tag(7), do: "rect"
  defp render_op_type_for_tag(8), do: "fillRect"
  defp render_op_type_for_tag(9), do: "circle"
  defp render_op_type_for_tag(10), do: "fillCircle"
  defp render_op_type_for_tag(12), do: "bitmapInRect"
  defp render_op_type_for_tag(13), do: "rotatedBitmap"
  defp render_op_type_for_tag(14), do: "drawVectorAt"
  defp render_op_type_for_tag(15), do: "vectorSequenceAt"
  defp render_op_type_for_tag(16), do: "pathFilled"
  defp render_op_type_for_tag(17), do: "pathOutline"
  defp render_op_type_for_tag(18), do: "pathOutlineOpen"
  defp render_op_type_for_tag(19), do: "roundRect"
  defp render_op_type_for_tag(20), do: "arc"
  defp render_op_type_for_tag(21), do: "fillRadial"
  defp render_op_type_for_tag(_), do: nil

  @spec render_op_args_for_tag(integer(), EvalTypes.runtime_value()) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
  defp render_op_args_for_tag(tag, payload) do
    case constructor_payload_args(payload, render_op_arg_count(tag)) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  @spec render_op_arg_count(integer()) :: non_neg_integer()
  defp render_op_arg_count(1), do: 3
  defp render_op_arg_count(2), do: 3
  defp render_op_arg_count(3), do: 3
  defp render_op_arg_count(4), do: 1
  defp render_op_arg_count(5), do: 2
  defp render_op_arg_count(6), do: 3
  defp render_op_arg_count(7), do: 2
  defp render_op_arg_count(8), do: 2
  defp render_op_arg_count(9), do: 3
  defp render_op_arg_count(10), do: 3
  defp render_op_arg_count(12), do: 2
  defp render_op_arg_count(13), do: 4
  defp render_op_arg_count(14), do: 2
  defp render_op_arg_count(15), do: 2
  defp render_op_arg_count(16), do: 1
  defp render_op_arg_count(17), do: 1
  defp render_op_arg_count(18), do: 1
  defp render_op_arg_count(19), do: 3
  defp render_op_arg_count(20), do: 6
  defp render_op_arg_count(21), do: 6
  defp render_op_arg_count(_), do: 1

  @spec normalize_render_op_fields(String.t(), [EvalTypes.runtime_value()], map()) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
  defp normalize_render_op_fields("bitmapInRect", [bitmap, bounds | _], eval_context) do
    with {:ok, bitmap_id} <- CoreIREvaluator.bitmap_resource_id_from_value(bitmap, eval_context),
         {:ok, {x, y, w, h}} <- CoreIREvaluator.normalize_runtime_rect(bounds) do
      {:ok, [bitmap_id, x, y, w, h]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("rotatedBitmap", [bitmap, src_rect, angle, center | _], eval_context) do
    with {:ok, bitmap_id} <- CoreIREvaluator.bitmap_resource_id_from_value(bitmap, eval_context),
         {:ok, {_src_x, _src_y, src_w, src_h}} <- CoreIREvaluator.normalize_runtime_rect(src_rect),
         {:ok, normalized_angle} <- CoreIREvaluator.normalize_runtime_rotation_angle(angle),
         {:ok, {center_x, center_y}} <- CoreIREvaluator.normalize_runtime_point(center) do
      {:ok, [bitmap_id, src_w, src_h, normalized_angle, center_x, center_y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("drawVectorAt", [vector, origin | _], eval_context) do
    with vector_id when is_integer(vector_id) <- resolve_render_vector_id(vector, eval_context),
         {:ok, {x, y}} <- CoreIREvaluator.normalize_runtime_point(origin) do
      {:ok, [vector_id, x, y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("vectorSequenceAt", [vector, origin | _], eval_context) do
    with vector_id when is_integer(vector_id) <-
           CoreIREvaluator.vector_resource_id_from_value(vector, eval_context),
         {:ok, {x, y}} <- CoreIREvaluator.normalize_runtime_point(origin) do
      {:ok, [vector_id, x, y]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("fillRect", [bounds, color | _], _eval_context) do
    with {:ok, {x, y, w, h}} <- CoreIREvaluator.normalize_runtime_rect(bounds),
         {:ok, resolved_color} <- CoreIREvaluator.normalize_runtime_color(color) do
      {:ok, [x, y, w, h, resolved_color]}
    else
      _ -> :error
    end
  end

  defp normalize_render_op_fields("clear", [color | _], _eval_context) do
    case CoreIREvaluator.normalize_runtime_color(color) do
      {:ok, resolved_color} -> {:ok, [resolved_color]}
      _ -> :error
    end
  end

  defp normalize_render_op_fields(_type, args, _eval_context) when is_list(args), do: {:ok, args}

  @spec resolve_render_vector_id(EvalTypes.runtime_value(), map()) :: integer() | nil
  defp resolve_render_vector_id(vector, eval_context) when is_map(eval_context) do
    indices = Map.get(eval_context, :vector_resource_indices, %{})
    runtime_model = Map.get(eval_context, :runtime_model, %{})
    from_ctor = vector_ctor_manifest_index(vector, indices)

    from_core =
      case CoreIREvaluator.vector_resource_id_from_value(vector, eval_context) do
        {:ok, id} -> id
        :error -> nil
      end

    from_model = vector_index_from_runtime_model(runtime_model, indices)

    cond do
      is_integer(from_ctor) ->
        from_ctor

      is_integer(from_model) and is_integer(from_core) ->
        min(from_model, from_core)

      is_integer(from_core) ->
        from_core

      is_integer(from_model) ->
        from_model

      true ->
        nil
    end
  end

  defp resolve_render_vector_id(_vector, _eval_context), do: nil

  @spec vector_ctor_manifest_index(EvalTypes.runtime_value(), map()) :: integer() | nil
  defp vector_ctor_manifest_index(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(ctor, indices)

  defp vector_ctor_manifest_index(%{ctor: ctor, args: _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(to_string(ctor), indices)

  defp vector_ctor_manifest_index(_vector, _indices), do: nil

  @spec normalize_pebble_context_group(EvalTypes.runtime_value(), map()) :: {:ok, map()} | :error
  defp normalize_pebble_context_group(value, eval_context) do
    with {:ok, 19, payload} <- tagged_constructor_value(value),
         {:ok, [settings, ops]} <- constructor_payload_args(payload, 2),
         {:ok, settings} <- constructor_list_values(settings),
         {:ok, ops} <- constructor_list_values(ops),
         style <- normalize_pebble_context_style(settings),
         {:ok, op_nodes} <-
           normalize_pebble_ui_list(ops, &normalize_pebble_render_op(&1, eval_context)) do
      {:ok, %{"type" => "group", "label" => "", "style" => style, "children" => op_nodes}}
    else
      _ -> :error
    end
  end

  @spec normalize_pebble_context_style([EvalTypes.runtime_value()]) :: map()
  defp normalize_pebble_context_style(settings) when is_list(settings) do
    Enum.reduce(settings, %{}, fn setting, acc ->
      case normalize_pebble_context_setting(setting) do
        {key, value} -> Map.put(acc, key, value)
        nil -> acc
      end
    end)
  end

  @spec normalize_pebble_context_setting(EvalTypes.runtime_value()) :: {String.t(), EvalTypes.runtime_value()} | nil
  defp normalize_pebble_context_setting(setting) do
    with {:ok, tag, value} <- tagged_constructor_value(setting),
         key when is_binary(key) <- context_setting_key(tag) do
      {key, normalized_context_setting_value(value)}
    else
      _ -> nil
    end
  end

  @spec context_setting_key(EvalTypes.runtime_value()) :: String.t() | nil
  defp context_setting_key(1), do: "stroke_width"
  defp context_setting_key(2), do: "antialiased"
  defp context_setting_key(3), do: "stroke_color"
  defp context_setting_key(4), do: "fill_color"
  defp context_setting_key(5), do: "text_color"
  defp context_setting_key(6), do: "compositing_mode"
  defp context_setting_key(_), do: nil

  @spec normalized_context_setting_value(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalized_context_setting_value(value) when is_integer(value) or is_boolean(value),
    do: value

  defp normalized_context_setting_value(value),
    do: normalized_expr_value(normalize_runtime_view_tree_fallback(value))

  @spec normalize_pebble_ui_list([EvalTypes.runtime_value()], SemTypes.pebble_ui_normalizer()) ::
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

  @spec tagged_tuple(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
  defp tagged_tuple({tag, payload}) when is_integer(tag), do: {:ok, tag, payload}
  defp tagged_tuple(_value), do: :error

  @spec tagged_constructor_value(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
  defp tagged_constructor_value(value) do
    case tagged_tuple(value) do
      {:ok, tag, payload} ->
        {:ok, tag, payload}

      :error ->
        normalized_tagged_tuple(value)
    end
  end

  @spec normalized_tagged_tuple(EvalTypes.runtime_value()) :: SemTypes.tagged_value()
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

  @spec normalized_expr_value(EvalTypes.runtime_value()) :: EvalTypes.runtime_value()
  defp normalized_expr_value(%{"type" => "expr"} = node), do: Map.get(node, "value")
  defp normalized_expr_value(%{type: "expr"} = node), do: Map.get(node, :value)
  defp normalized_expr_value(_node), do: nil

  @spec constructor_list_values(EvalTypes.runtime_value()) :: SemTypes.tagged_values()
  defp constructor_list_values(values) when is_list(values), do: {:ok, values}

  defp constructor_list_values(%{"type" => "List", "children" => children})
       when is_list(children),
       do: {:ok, children}

  defp constructor_list_values(%{type: "List", children: children}) when is_list(children),
    do: {:ok, children}

  defp constructor_list_values(_values), do: :error

  @spec constructor_payload_args(EvalTypes.runtime_value(), non_neg_integer()) :: SemTypes.tagged_values()
  defp constructor_payload_args(payload, 1), do: {:ok, [payload]}

  defp constructor_payload_args(payload, arity) when is_integer(arity) and arity > 1 do
    case flatten_constructor_payload(payload, arity, []) do
      {:ok, args} -> {:ok, args}
      :error -> :error
    end
  end

  @spec flatten_constructor_payload(EvalTypes.runtime_value(), non_neg_integer(), [EvalTypes.runtime_value()]) ::
          {:ok, [EvalTypes.runtime_value()]} | :error
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

  @spec evaluator_context(map(), String.t() | nil) :: SemTypes.eval_context()
  defp evaluator_context(core_ir, module_override) do
    module_name =
      case module_override do
        value when is_binary(value) and value != "" -> value
        _ -> CoreIREvaluator.entry_module(core_ir)
      end

    CoreIREvaluator.build_eval_context(core_ir, module_name)
  end

  @spec normalize_runtime_model_by_declared_type(map(), map()) :: map()
  defp normalize_runtime_model_by_declared_type(runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    CoreIREvaluator.normalize_value_by_type(runtime_model, "Model", eval_context)
  end

  defp normalize_runtime_model_by_declared_type(runtime_model, _eval_context), do: runtime_model

  @view_runtime_envelope_keys [
    "runtime_model",
    "runtime_view_output",
    "runtime_last_message",
    "runtime_message_source",
    "runtime_message_cursor",
    "runtime_known_messages",
    "runtime_update_branches",
    "runtime_view_tree_sha256",
    "runtime_model_sha256",
    "runtime_model_source",
    "elm_executor_mode",
    "elm_executor",
    "elm_introspect",
    "vector_resource_indices",
    "bitmap_resource_indices",
    "elm_executor_core_ir",
    "elm_executor_core_ir_b64",
    "elm_executor_metadata"
  ]

  @spec enrich_runtime_model_for_view(map(), map()) :: map()
  defp enrich_runtime_model_for_view(runtime_model, current_model)
       when is_map(runtime_model) and is_map(current_model) do
    current_model
    |> Map.drop(@view_runtime_envelope_keys)
    |> Map.merge(runtime_model)
  end

  defp enrich_runtime_model_for_view(runtime_model, _current_model) when is_map(runtime_model),
    do: runtime_model

  defp enrich_runtime_model_for_view(_runtime_model, _current_model), do: %{}

  @spec source_core_ir_fallback(map() | nil, String.t(), String.t() | nil) :: map() | nil
  defp source_core_ir_fallback(core_ir, _source, _rel_path) when is_map(core_ir), do: core_ir

  defp source_core_ir_fallback(_core_ir, source, rel_path)
       when is_binary(source) and byte_size(source) > 0 do
    path =
      case rel_path do
        value when is_binary(value) and value != "" -> value
        _ -> "Main.elm"
      end

    with {:ok, main_module} <- GeneratedParser.parse_source(path, source),
         extra_modules <- load_resource_modules_for_path(path),
         project <- %Project{
           project_dir: path |> Path.dirname() |> Path.expand(),
           elm_json: %{},
           modules: [main_module | extra_modules],
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

  @spec load_resource_modules_for_path(String.t()) :: [map()]
  defp load_resource_modules_for_path(main_path) when is_binary(main_path) do
    resources_path =
      main_path
      |> Path.dirname()
      |> Path.join("Pebble/Ui/Resources.elm")

    case File.read(resources_path) do
      {:ok, source} ->
        case GeneratedParser.parse_source(resources_path, source) do
          {:ok, module} -> [module]
          _ -> []
        end

      _ ->
        []
    end
  end

  @spec vector_resource_indices_context(map(), map()) :: map()
  defp vector_resource_indices_context(request, current_model)
       when is_map(request) and is_map(current_model) do
    indices =
      map_value(request, :vector_resource_indices) ||
        Map.get(current_model, "vector_resource_indices") ||
        Map.get(current_model, :vector_resource_indices)

    case normalize_vector_resource_indices(indices) do
      %{} = normalized when map_size(normalized) > 0 ->
        %{vector_resource_indices: normalized}

      _ ->
        %{}
    end
  end

  defp vector_resource_indices_context(_request, _current_model), do: %{}

  @spec bitmap_resource_indices_context(map(), map()) :: map()
  defp bitmap_resource_indices_context(request, current_model)
       when is_map(request) and is_map(current_model) do
    indices =
      map_value(request, :bitmap_resource_indices) ||
        Map.get(current_model, "bitmap_resource_indices") ||
        Map.get(current_model, :bitmap_resource_indices)

    case normalize_bitmap_resource_indices(indices) do
      %{} = normalized when map_size(normalized) > 0 ->
        %{bitmap_resource_indices: normalized}

      _ ->
        %{}
    end
  end

  defp bitmap_resource_indices_context(_request, _current_model), do: %{}

  @spec normalize_bitmap_resource_indices(map() | nil) :: map()
  defp normalize_bitmap_resource_indices(indices) when is_map(indices) do
    Enum.reduce(indices, %{}, fn
      {ctor, id}, acc when is_binary(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, ctor, id)

      {ctor, id}, acc when is_atom(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, Atom.to_string(ctor), id)

      _, acc ->
        acc
    end)
  end

  defp normalize_bitmap_resource_indices(_indices), do: %{}

  @spec normalize_vector_resource_indices(map() | nil) :: map()
  defp normalize_vector_resource_indices(indices) when is_map(indices) do
    Enum.reduce(indices, %{}, fn
      {ctor, id}, acc when is_binary(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, ctor, id)

      {ctor, id}, acc when is_atom(ctor) and is_integer(id) and id >= 1 ->
        Map.put(acc, Atom.to_string(ctor), id)

      _, acc ->
        acc
    end)
  end

  defp normalize_vector_resource_indices(_indices), do: %{}

  @spec normalize_launch_context(SemTypes.launch_context()) :: SemTypes.launch_context()
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
          launch_context_screen(value, context)

        _ ->
          launch_context_screen(%{}, context)
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
    |> Map.put(
      "hasMicrophone",
      map_value(context, :has_microphone) || map_value(context, :hasMicrophone) || false
    )
    |> Map.put(
      "hasCompass",
      map_value(context, :has_compass) || map_value(context, :hasCompass) || false
    )
    |> Map.put(
      "supportsHealth",
      map_value(context, :supports_health) || map_value(context, :supportsHealth) || false
    )
  end

  defp normalize_launch_context(_context) do
    normalize_launch_context(%{})
  end

  @spec launch_context_from_model(map()) :: map()
  defp launch_context_from_model(model) when is_map(model) do
    Map.get(model, "launch_context") || Map.get(model, :launch_context) || %{}
  end

  defp launch_context_from_model(_model), do: %{}

  @spec launch_context_screen(map(), map()) :: map()
  defp launch_context_screen(screen, context) when is_map(screen) and is_map(context) do
    shape_name = launch_context_display_shape(screen, context)
    color_name = launch_context_color_mode_value(screen, context)

    %{
      "width" => map_value(screen, :width) || map_value(context, :screenW) || 144,
      "height" => map_value(screen, :height) || map_value(context, :screenH) || 168,
      "shape" => launch_context_display_shape_ctor(shape_name),
      "color_mode" => color_name,
      "colorMode" => launch_context_color_mode_ctor(color_name)
    }
  end

  @spec launch_context_display_shape_ctor(String.t()) :: map()
  defp launch_context_display_shape_ctor("Round"), do: %{"ctor" => "Round", "args" => []}
  defp launch_context_display_shape_ctor(_), do: %{"ctor" => "Rectangular", "args" => []}

  @spec launch_context_color_mode_ctor(String.t()) :: map()
  defp launch_context_color_mode_ctor("BlackWhite"), do: %{"ctor" => "BlackWhite", "args" => []}
  defp launch_context_color_mode_ctor("Color"), do: %{"ctor" => "Color", "args" => []}
  defp launch_context_color_mode_ctor(_), do: %{"ctor" => "Color", "args" => []}

  @spec launch_context_display_shape(map(), map()) :: String.t()
  defp launch_context_display_shape(screen, context) when is_map(screen) and is_map(context) do
    cond do
      map_value(screen, :shape) in ["Round", "Rectangular"] ->
        map_value(screen, :shape)

      map_value(screen, :shape) == "round" ->
        "Round"

      map_value(screen, :shape) == "rect" ->
        "Rectangular"

      map_value(screen, :is_round) == true or map_value(screen, :isRound) == true ->
        "Round"

      map_value(screen, :is_round) == false or map_value(screen, :isRound) == false ->
        "Rectangular"

      map_value(context, :shape) == "round" ->
        "Round"

      map_value(context, :shape) == "rect" ->
        "Rectangular"

      true ->
        "Rectangular"
    end
  end

  @spec launch_context_color_mode_value(map(), map()) :: String.t()
  defp launch_context_color_mode_value(screen, context) when is_map(screen) and is_map(context) do
    cond do
      map_value(screen, :color_mode) in ["Color", "BlackWhite"] ->
        map_value(screen, :color_mode)

      map_value(screen, :colorMode) in ["Color", "BlackWhite"] ->
        map_value(screen, :colorMode)

      map_value(screen, :is_color) == true or map_value(screen, :isColor) == true ->
        "Color"

      map_value(screen, :is_color) == false or map_value(screen, :isColor) == false ->
        "BlackWhite"

      map_value(context, :is_color) == true ->
        "Color"

      map_value(context, :is_color) == false ->
        "BlackWhite"

      true ->
        "Color"
    end
  end

  @spec launch_reason_value(String.t()) :: map()
  defp launch_reason_value(value) when is_binary(value) and value != "",
    do: %{"ctor" => value, "args" => []}

  defp launch_reason_value(_value), do: %{"ctor" => "LaunchUser", "args" => []}

  @spec derive_view_output(map(), map(), map()) :: SemTypes.view_output()
  defp derive_view_output(view_tree, runtime_model, eval_context)
       when is_map(view_tree) and is_map(runtime_model) and is_map(eval_context) do
    view_output_from_tree(view_tree, runtime_model, eval_context)
  end

  defp derive_view_output(_view_tree, _runtime_model, _eval_context), do: []

  @spec view_output_from_tree(map(), map(), map()) :: SemTypes.view_output()
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

      type
      when type in [
             "root",
             "windowStack",
             "window",
             "canvasLayer",
             "List",
             "append",
             "__append__",
             "toUiNode",
             "call",
             "expr",
             "tuple2",
             "CanvasLayer"
           ] ->
        Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))

      _ ->
        view_output_from_node(node, runtime_model, eval_context)
    end
  end

  defp view_output_from_tree(_node, _runtime_model, _eval_context), do: []

  @spec view_output_style_rows(map()) :: [SemTypes.view_output_row()]
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

  @spec style_value(map(), String.t()) :: EvalTypes.runtime_value() | nil
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

  @spec view_output_from_node(map(), map(), map()) :: SemTypes.view_output()
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

        type when type in ["drawVectorAt", "vectorAt"] ->
          case vector_at_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [vector_id, x, y]} ->
              [%{"kind" => "vector_at", "vector_id" => vector_id, "x" => x, "y" => y}]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
          end

        type when type in ["drawVectorSequenceAt", "vectorSequenceAt"] ->
          case vector_at_args_from_node(node, ints, runtime_model, eval_context) do
            {:ok, [vector_id, x, y]} ->
              [
                %{"kind" => "vector_sequence_at", "vector_id" => vector_id, "x" => x, "y" => y}
              ]

            :error ->
              [unresolved_view_output_row(node, type, ints, 3)]
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
            {:ok, [font_id, x, y, w, h, alignment, overflow, text]}
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
                  "font_id" => font_id,
                  "text_align" => text_alignment_name(alignment),
                  "text_overflow" => text_overflow_name(overflow)
                }
              ]

            _ ->
              [unresolved_view_output_row(node, type, ints, 6)]
          end

        _ ->
          view_output_from_introspect_helper(node, runtime_model, eval_context)
      end

    Enum.map(rows, &put_view_output_source(&1, node))
  end

  defp view_output_from_node(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_introspect_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_introspect_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case helper_return_kind(node, eval_context) do
      :list_render_op -> view_output_from_list_render_op_helper(node, runtime_model, eval_context)
      :render_op -> view_output_from_render_op_helper(node, runtime_model, eval_context)
      _ -> []
    end
  end

  defp view_output_from_introspect_helper(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_list_render_op_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_list_render_op_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    call_site_rows =
      node
      |> node_children()
      |> Enum.flat_map(&collect_subtree_view_output(&1, runtime_model, eval_context))

    if call_site_rows != [] do
      call_site_rows
    else
      view_output_from_helper_function_body(node, runtime_model, eval_context)
    end
  end

  defp view_output_from_list_render_op_helper(_node, _runtime_model, _eval_context), do: []

  @spec view_output_from_helper_function_body(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_helper_function_body(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    with %{} = ei <- Map.get(eval_context, :elm_introspect),
         target when is_binary(target) <- view_tree_helper_target(node),
         {module_name, function_name} <- resolve_helper_function(ei, target),
         arity <- helper_call_arity(node),
         key <- "#{module_name}|#{function_name}|#{arity}",
         %{} = body_tree <-
           get_in(ei, ["function_view_trees", key]) ||
             get_in(ei, [:function_view_trees, key]) do
      eval_context =
        eval_context
        |> Map.put(:view_param_bindings, helper_param_bindings(node, runtime_model, eval_context, key, ei))

      collect_subtree_view_output(body_tree, runtime_model, eval_context)
    else
      _ -> []
    end
  end

  defp view_output_from_helper_function_body(_node, _runtime_model, _eval_context), do: []

  @spec helper_param_bindings(map(), map(), map(), String.t(), map()) :: map()
  defp helper_param_bindings(call_node, runtime_model, eval_context, function_key, ei)
       when is_map(call_node) and is_map(runtime_model) and is_map(eval_context) and is_binary(function_key) and
              is_map(ei) do
    arg_names = Map.get(call_node, "arg_names") || []
    param_types = helper_param_types(ei, function_key, length(arg_names))

    call_node
    |> node_children()
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {child, index}, acc ->
      name = Enum.at(arg_names, index)
      type = Enum.at(param_types, index)

      if is_binary(name) and name != "" do
        value =
          case evaluate_view_tree_value(child, runtime_model, eval_context) do
            nil -> fallback_helper_param_value(type, runtime_model)
            bound -> bound
          end

        if is_nil(value), do: acc, else: Map.put(acc, name, value)
      else
        acc
      end
    end)
  end

  defp helper_param_bindings(_call_node, _runtime_model, _eval_context, _function_key, _ei), do: %{}

  @spec helper_param_types(map(), String.t(), non_neg_integer()) :: [String.t()]
  defp helper_param_types(ei, function_key, arity) when is_map(ei) and is_binary(function_key) do
    case Map.get(Map.get(ei, "function_types") || %{}, function_key) do
      signature when is_binary(signature) ->
        signature
        |> String.split("->")
        |> Enum.map(&String.trim/1)
        |> Enum.take(arity)

      _ ->
        []
    end
  end

  @spec fallback_helper_param_value(String.t() | nil, map()) :: term()
  defp fallback_helper_param_value(type, runtime_model) when is_map(runtime_model) do
    normalized = if is_binary(type), do: String.downcase(type), else: ""

    cond do
      String.contains?(normalized, "point") ->
        case {model_screen_dimension(runtime_model, "screenW"), model_screen_dimension(runtime_model, "screenH")} do
          {w, h} when is_integer(w) and is_integer(h) ->
            %{"ctor" => "Point", "args" => [div(w, 2), div(h, 2)]}

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp fallback_helper_param_value(_type, _runtime_model), do: nil

  @spec view_output_from_render_op_helper(map(), map(), map()) :: SemTypes.view_output()
  defp view_output_from_render_op_helper(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    children = node_children(node)

    with [_model_node, _color_node, y_node, height_node, text_node | _] <- children,
         y when is_integer(y) <- eval_view_int(y_node, runtime_model, eval_context),
         height when is_integer(height) <- eval_view_int(height_node, runtime_model, eval_context),
         w when is_integer(w) <- model_screen_dimension(runtime_model, "screenW"),
         text when is_binary(text) <- helper_string_value(text_node, runtime_model, eval_context) do
      [%{
        "kind" => "text",
        "x" => 0,
        "y" => y,
        "w" => w,
        "h" => height,
        "text" => text,
        "font_id" => 0,
        "text_align" => "center",
        "text_overflow" => "fill"
      }]
    else
      _ ->
        Enum.flat_map(children, &view_output_from_tree(&1, runtime_model, eval_context))
    end
  end

  defp view_output_from_render_op_helper(_node, _runtime_model, _eval_context), do: []

  @spec helper_string_value(map(), map(), map()) :: String.t() | nil
  defp helper_string_value(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    eval_view_text(node, runtime_model, eval_context)
  end

  defp helper_string_value(_node, _runtime_model, _eval_context), do: nil

  @subtree_container_types ~w(
    root windowStack window canvasLayer List append __append__ toUiNode call expr tuple2
    CanvasLayer case if Then Else In record field var qualified_call constructor_call
  )

  @spec collect_subtree_view_output(map(), map(), map()) :: SemTypes.view_output()
  defp collect_subtree_view_output(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = view_tree_node_type(node)

    node_rows =
      if type in @subtree_container_types do
        []
      else
        view_output_from_node(node, runtime_model, eval_context)
      end

    child_rows =
      node
      |> node_children()
      |> Enum.flat_map(&collect_subtree_view_output(&1, runtime_model, eval_context))

    node_rows ++ child_rows
  end

  defp collect_subtree_view_output(_node, _runtime_model, _eval_context), do: []

  @spec view_tree_node_type(map()) :: String.t()
  defp view_tree_node_type(node) when is_map(node) do
    node
    |> Map.get("type", Map.get(node, :type, ""))
    |> to_string()
  end

  defp view_tree_node_type(_node), do: ""

  @spec model_screen_dimension(map(), String.t()) :: integer() | nil
  defp model_screen_dimension(runtime_model, key) when is_map(runtime_model) and is_binary(key) do
    aliases =
      case key do
        "screenW" -> ["screenW", "screen_width", "screenWidth"]
        "screenH" -> ["screenH", "screen_height", "screenHeight"]
        _ -> [key]
      end

    Enum.find_value(aliases, fn alias_key ->
      case model_value_by_key(runtime_model, alias_key) do
        value when is_integer(value) -> value
        _ -> nil
      end
    end)
  end

  defp model_screen_dimension(_runtime_model, _key), do: nil

  @spec helper_return_kind(map(), map()) :: :list_render_op | :render_op | :string | :unknown
  defp helper_return_kind(node, eval_context) when is_map(node) and is_map(eval_context) do
    with %{} = ei <- Map.get(eval_context, :elm_introspect),
         target when is_binary(target) <- view_tree_helper_target(node),
         {module_name, function_name} <- resolve_helper_function(ei, target),
         arity <- helper_call_arity(node),
         key <- "#{module_name}|#{function_name}|#{arity}",
         signature when is_binary(signature) <-
           Map.get(Map.get(ei, "function_types") || %{}, key) do
      normalized =
        signature
        |> String.replace(~r/\s+/, "")
        |> String.downcase()

      cond do
        String.match?(normalized, ~r/list.*renderop/) -> :list_render_op
        String.match?(normalized, ~r/->renderop$/) -> :render_op
        String.match?(normalized, ~r/->.*string$/) -> :string
        true -> :unknown
      end
    else
      _ -> :unknown
    end
  end

  defp helper_return_kind(_node, _eval_context), do: :unknown

  @spec view_tree_helper_target(map()) :: String.t() | nil
  defp view_tree_helper_target(node) when is_map(node) do
    Map.get(node, "qualified_target") ||
      case {Map.get(node, "label"), Map.get(node, "type")} do
        {name, name} when is_binary(name) -> name
        {label, _} when is_binary(label) -> label
        {_, type} when is_binary(type) -> type
        _ -> nil
      end
  end

  defp view_tree_helper_target(_node), do: nil

  @spec resolve_helper_function(map(), String.t()) :: {String.t(), String.t()} | nil
  defp resolve_helper_function(ei, target) when is_map(ei) and is_binary(target) do
    module_name = Map.get(ei, "module")

    cond do
      is_binary(module_name) and not String.contains?(target, ".") ->
        {module_name, target}

      String.contains?(target, ".") ->
        case String.split(target, ".") do
          [mod, fun] -> {mod, fun}
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp resolve_helper_function(_ei, _target), do: nil

  @spec helper_call_arity(map()) :: non_neg_integer()
  defp helper_call_arity(node) when is_map(node) do
    node
    |> node_children()
    |> length()
  end

  defp helper_call_arity(_node), do: 0

  @spec put_view_output_source(SemTypes.view_output_row(), map()) :: SemTypes.view_output_row()
  defp put_view_output_source(row, node) when is_map(row) and is_map(node) do
    case Map.get(node, "source") || Map.get(node, :source) do
      %{} = source -> Map.put(row, "source", source)
      _ -> row
    end
  end

  defp put_view_output_source(row, _node), do: row

  @spec annotate_view_output_sources(SemTypes.view_output(), map()) :: SemTypes.view_output()
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

  @spec source_location_at([map()], non_neg_integer()) :: map() | nil
  defp source_location_at(locations, index) when is_list(locations) and locations != [] do
    Enum.at(locations, index) || List.last(locations)
  end

  defp source_location_at(_locations, _index), do: nil

  @spec node_int_args(map(), map(), map()) :: [integer()]
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

  @spec min_int_arity_for_node(map()) :: non_neg_integer()
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
      "drawVectorAt" -> 3
      "vectorAt" -> 3
      "drawVectorSequenceAt" -> 3
      "vectorSequenceAt" -> 3
      "pixel" -> 3
      "textInt" -> 4
      "textLabel" -> 3
      _ -> 1
    end
  end

  @spec require_ints([integer()], non_neg_integer()) :: {:ok, [integer()]} | :error
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

  @spec unresolved_view_output_row(map(), String.t(), [integer()], non_neg_integer()) :: SemTypes.view_output_row()
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

  @spec vector_at_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
  defp vector_at_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 3) do
      {:ok, [vector_id, x, y]} ->
        {:ok, [vector_id, x, y]}

      :error ->
        case node_children(node) do
          [vector_node, x_node, y_node | _] ->
            with vector_id when is_integer(vector_id) <-
                   preview_vector_id(vector_node, runtime_model, eval_context),
                 x when is_integer(x) <- eval_view_int(x_node, runtime_model, eval_context),
                 y when is_integer(y) <- eval_view_int(y_node, runtime_model, eval_context) do
              {:ok, [vector_id, x, y]}
            else
              _ -> :error
            end

          [vector_node, point_node | _] ->
            with vector_id when is_integer(vector_id) <-
                   preview_vector_id(vector_node, runtime_model, eval_context),
                 {:ok, [x, y]} <- point_pair_from_node(point_node, runtime_model, eval_context) do
              {:ok, [vector_id, x, y]}
            else
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp vector_at_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  @spec eval_view_vector_id(map() | EvalTypes.runtime_value(), map()) :: integer() | nil
  defp eval_view_vector_id(value, context)

  defp eval_view_vector_id(%{"type" => "expr", "value" => value}, context),
    do: eval_view_vector_id(value, context)

  defp eval_view_vector_id(%{type: "expr", value: value}, context),
    do: eval_view_vector_id(value, context)

  defp eval_view_vector_id(value, context) do
    case CoreIREvaluator.vector_resource_id_from_value(value, context) do
      {:ok, id} ->
        id

      :error ->
        if is_map(value) and Map.has_key?(value, "type"), do: vector_id_from_view_tree_node(value, context), else: nil
    end
  end

  @spec vector_id_from_view_tree_node(map(), map()) :: integer() | nil
  defp vector_id_from_view_tree_node(node, context) when is_map(node) and is_map(context) do
    indices = Map.get(context, :vector_resource_indices) || %{}
    runtime_model = Map.get(context, :runtime_model) || %{}

    id_from_model = vector_index_from_runtime_model(runtime_model, indices)

    id_from_arg =
      with [arg_node | _] <- node_children(node),
           value when not is_nil(value) <-
             eval_tree_expr_value(arg_node, runtime_model, context) || value_from_runtime_model(runtime_model),
           id when is_integer(id) <- vector_index_for_runtime_value(value, indices) do
        id
      else
        _ -> nil
      end

    id_from_arg || id_from_model
  end

  defp vector_id_from_view_tree_node(_node, _context), do: nil

  @spec preview_vector_id(map() | term(), map(), map()) :: integer() | nil
  defp preview_vector_id(vector_node, runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    indices = Map.get(eval_context, :vector_resource_indices) || %{}

    eval_context =
      if map_size(Map.get(eval_context, :runtime_model) || %{}) > 0,
        do: eval_context,
        else: Map.put(eval_context, :runtime_model, runtime_model)

    id_from_model = vector_index_from_runtime_model(runtime_model, indices)
    id_from_node = eval_view_vector_id(vector_node, eval_context)

    cond do
      is_integer(id_from_model) and vector_preview_prefers_model_scan?(vector_node) ->
        id_from_model

      true ->
        [id_from_model, id_from_node]
        |> Enum.filter(&is_integer/1)
        |> case do
          [] -> nil
          ids -> Enum.min(ids)
        end
    end
  end

  defp preview_vector_id(_vector_node, _runtime_model, _eval_context), do: nil

  @spec vector_preview_prefers_model_scan?(map()) :: boolean()
  defp vector_preview_prefers_model_scan?(node) when is_map(node) do
    type = view_tree_node_type(node)

    type != "" and type not in ["var", "expr", "field", "record", "group"] and
      not String.starts_with?(type, "drawVector")
  end

  defp vector_preview_prefers_model_scan?(_node), do: false

  @spec value_from_runtime_model(map()) :: map() | nil
  defp value_from_runtime_model(runtime_model) when is_map(runtime_model) do
    Enum.find_value(runtime_model, fn
      {_key, %{"ctor" => "Just", "args" => [inner]} = value} when is_map(inner) -> value
      _ -> nil
    end)
  end

  defp value_from_runtime_model(_runtime_model), do: nil

  @spec vector_index_from_runtime_model(map(), map()) :: integer() | nil
  defp vector_index_from_runtime_model(runtime_model, indices)
       when is_map(runtime_model) and is_map(indices) do
    runtime_model
    |> Map.values()
    |> Enum.flat_map(&vector_index_ids_for_runtime_value(&1, indices))
    |> case do
      [] -> nil
      ids -> Enum.min(ids)
    end
  end

  defp vector_index_from_runtime_model(_runtime_model, _indices), do: nil

  @spec vector_index_ids_for_runtime_value(term(), map()) :: [integer()]
  defp vector_index_ids_for_runtime_value(%{"ctor" => "Just", "args" => [inner]}, indices),
    do: vector_index_ids_for_runtime_value(inner, indices)

  defp vector_index_ids_for_runtime_value(%{ctor: "Just", args: [inner]}, indices),
    do: vector_index_ids_for_runtime_value(inner, indices)

  defp vector_index_ids_for_runtime_value(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor) do
    case vector_index_for_runtime_ctor(ctor, indices) do
      id when is_integer(id) -> [id]
      _ -> []
    end
  end

  defp vector_index_ids_for_runtime_value(%{ctor: ctor, args: _}, indices) when is_binary(ctor) do
    case vector_index_for_runtime_ctor(to_string(ctor), indices) do
      id when is_integer(id) -> [id]
      _ -> []
    end
  end

  defp vector_index_ids_for_runtime_value(_value, _indices), do: []

  @spec vector_index_for_runtime_value(term(), map()) :: integer() | nil
  defp vector_index_for_runtime_value(%{"ctor" => "Just", "args" => [inner]}, indices),
    do: vector_index_for_runtime_value(inner, indices)

  defp vector_index_for_runtime_value(%{ctor: "Just", args: [inner]}, indices),
    do: vector_index_for_runtime_value(inner, indices)

  defp vector_index_for_runtime_value(%{"ctor" => ctor, "args" => _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(ctor, indices)

  defp vector_index_for_runtime_value(%{ctor: ctor, args: _}, indices) when is_binary(ctor),
    do: vector_index_for_runtime_ctor(to_string(ctor), indices)

  defp vector_index_for_runtime_value(_value, _indices), do: nil

  @spec vector_index_for_runtime_ctor(String.t(), map()) :: integer() | nil
  defp vector_index_for_runtime_ctor(ctor, indices) when is_binary(ctor) and is_map(indices) do
    ctor = to_string(ctor)

    case Map.get(indices, ctor) do
      id when is_integer(id) ->
        id

      _ ->
        indices
        |> Enum.filter(fn {key, _id} -> String.ends_with?(to_string(key), ctor) end)
        |> case do
          [] ->
            nil

          [{_key, id}] ->
            id

          matches ->
            matches
            |> Enum.min_by(fn {key, _id} -> byte_size(to_string(key)) end)
            |> then(fn {_key, id} -> id end)
        end
    end
  end

  defp vector_index_for_runtime_ctor(_ctor, _indices), do: nil

  @spec clear_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec line_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec circle_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec rect_color_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec round_rect_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec rect_angle_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec text_int_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args()
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

  @spec text_label_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args_mixed()
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

  @spec eval_view_font_id(map(), map(), map()) :: integer() | nil
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
          String.contains?(type, "defaultfont") -> 1
          String.contains?(type, "uifont") -> 1
          String.contains?(label, "defaultfont") -> 1
          String.contains?(label, "uifont") -> 1
          true -> nil
        end
    end
  end

  defp eval_view_font_id(_node, _runtime_model, _eval_context), do: nil

  @spec rect_quad_from_node(map(), map(), map()) :: SemTypes.draw_args()
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

  @spec path_args_from_node(map(), map(), map()) :: SemTypes.path_args()
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

  @spec path_points_from_node(map(), map(), map()) :: SemTypes.point_list()
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

  @spec point_pair_from_node(map(), map(), map()) :: SemTypes.point_pair()
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
        case record_point_coords_from_node(node, runtime_model, eval_context) do
          {:ok, coords} -> {:ok, coords}
          :error -> :error
        end

      {"expr", "record_literal"} ->
        record_point_coords_from_node(node, runtime_model, eval_context)

      {"var", _} ->
        case view_binding_value(view_var_name(node), runtime_model, eval_context)
             |> point_coords_from_value() do
          {:ok, coords} ->
            {:ok, coords}

          :error ->
            screen_center_point(runtime_model)
        end

      _ ->
        :error
    end
  end

  defp point_pair_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec screen_center_point(map()) :: SemTypes.point_pair()
  defp screen_center_point(runtime_model) when is_map(runtime_model) do
    case {model_screen_dimension(runtime_model, "screenW"), model_screen_dimension(runtime_model, "screenH")} do
      {w, h} when is_integer(w) and is_integer(h) -> {:ok, [div(w, 2), div(h, 2)]}
      _ -> :error
    end
  end

  defp screen_center_point(_runtime_model), do: :error

  @spec field_value_int(map() | nil, map(), map()) :: integer() | nil
  defp field_value_int(field_node, runtime_model, eval_context)
       when is_map(field_node) and is_map(runtime_model) and is_map(eval_context) do
    case node_children(field_node) do
      [value_node | _] -> eval_view_int(value_node, runtime_model, eval_context)
      _ -> nil
    end
  end

  defp field_value_int(_field_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_color(map(), map(), map()) :: integer() | nil
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

  @spec node_children(map()) :: [map()]
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

  @spec eval_view_int(map(), map(), map()) :: integer() | nil
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

  @spec eval_view_int_fallback(map(), map(), map()) :: integer() | nil
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
        var_name = view_var_name(node)

        cond do
          is_integer(view_binding_value(var_name, runtime_model, eval_context)) ->
            view_binding_value(var_name, runtime_model, eval_context)

          is_float(view_binding_value(var_name, runtime_model, eval_context)) ->
            trunc(view_binding_value(var_name, runtime_model, eval_context))

          is_integer(Map.get(runtime_model, var_name)) ->
            Map.get(runtime_model, var_name)

          is_float(Map.get(runtime_model, var_name)) ->
            trunc(Map.get(runtime_model, var_name))

          true ->
            Enum.find_value(children, &eval_view_int(&1, runtime_model, eval_context))
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

  @spec eval_view_text(map(), map(), map()) :: String.t() | nil
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

  @spec eval_tree_expr_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
  defp eval_tree_expr_value(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        case CoreIREvaluator.evaluate(expr, view_eval_env(runtime_model, eval_context), eval_context) do
          {:ok, value} -> value
          _ -> nil
        end
    end
  end

  defp eval_tree_expr_value(_node, _runtime_model, _eval_context), do: nil

  @spec view_eval_env(map(), map()) :: map()
  defp view_eval_env(runtime_model, eval_context) when is_map(runtime_model) and is_map(eval_context) do
    bindings = Map.get(eval_context, :view_param_bindings) || %{}

    runtime_model
    |> Map.put("model", runtime_model)
    |> Map.merge(bindings)
  end

  @spec view_var_name(map()) :: String.t()
  defp view_var_name(node) when is_map(node) do
    node
    |> then(fn n -> n["value"] || n[:value] || n["label"] || n[:label] || "" end)
    |> to_string()
  end

  @spec view_binding_value(String.t(), map(), map()) :: term()
  defp view_binding_value(name, runtime_model, eval_context)
       when is_binary(name) and name != "" and is_map(runtime_model) and is_map(eval_context) do
    Map.get(view_eval_env(runtime_model, eval_context), name)
  end

  defp view_binding_value(_name, _runtime_model, _eval_context), do: nil

  @spec point_coords_from_value(term()) :: SemTypes.point_pair()
  defp point_coords_from_value(%{"ctor" => "Point", "args" => [x, y]})
       when is_integer(x) and is_integer(y),
       do: {:ok, [x, y]}

  defp point_coords_from_value(%{ctor: "Point", args: [x, y]})
       when is_integer(x) and is_integer(y),
       do: {:ok, [x, y]}

  defp point_coords_from_value(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  defp point_coords_from_value(%{x: x, y: y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  defp point_coords_from_value(_value), do: :error

  @spec record_point_coords_from_node(map(), map(), map()) :: SemTypes.point_pair()
  defp record_point_coords_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    fields =
      node
      |> node_children()
      |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") in ["field", "record_field"]))

    x_value =
      fields
      |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
      |> field_value_int(runtime_model, eval_context)

    y_value =
      fields
      |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
      |> field_value_int(runtime_model, eval_context)

    if is_integer(x_value) and is_integer(y_value), do: {:ok, [x_value, y_value]}, else: :error
  end

  defp record_point_coords_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec normalize_text_value(EvalTypes.runtime_value()) :: String.t() | nil
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

  @spec model_value_by_key(map(), String.t()) :: EvalTypes.runtime_value() | nil
  defp model_value_by_key(model, key) when is_map(model) and is_binary(key) do
    Map.get(model, key) ||
      Enum.find_value(model, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value, else: nil

        _ ->
          nil
      end)
  end

  @spec eval_tree_expr_int(map(), map(), map()) :: integer() | nil
  defp eval_tree_expr_int(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        case CoreIREvaluator.evaluate(expr, view_eval_env(runtime_model, eval_context), eval_context) do
          {:ok, value} when is_integer(value) -> value
          {:ok, value} when is_float(value) -> trunc(value)
          _ -> nil
        end
    end
  end

  defp eval_tree_expr_int(_node, _runtime_model, _eval_context), do: nil

  @spec tree_node_to_expr(map()) :: SemTypes.expr()
  defp tree_node_to_expr(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")
    value = node["value"] || node[:value]
    children = (node["children"] || node[:children] || []) |> Enum.filter(&is_map/1)
    qualified_target = Map.get(node, "qualified_target") || Map.get(node, :qualified_target)

    cond do
      type == "var" and children != [] ->
        tree_node_to_expr(hd(children))

      type == "var" and label != "" ->
        %{"op" => :var, "name" => label}

      is_binary(qualified_target) and qualified_target != "" ->
        %{
          "op" => :qualified_call,
          "target" => qualified_target,
          "args" => Enum.map(children, &tree_node_to_expr/1)
        }

      type == "call" and label != "" ->
        %{"op" => :call, "name" => label, "args" => Enum.map(children, &tree_node_to_expr/1)}

      type != "" and type not in ["expr", "var", "field", "record", "group", "clear", "text"] and
          label == type ->
        %{"op" => :call, "name" => type, "args" => Enum.map(children, &tree_node_to_expr/1)}

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

  @spec eval_int_call(String.t(), [integer() | nil]) :: integer() | nil
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

  @spec extract_ints(String.t()) :: [integer()]
  defp extract_ints(text) when is_binary(text) do
    Regex.scan(~r/-?\d+/, text)
    |> Enum.map(fn [raw] -> String.to_integer(raw) end)
  end

  @spec text_label_from_node(map(), map(), map()) :: String.t()
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

  @spec text_args_from_node(map(), [integer()], map(), map()) :: SemTypes.draw_args_mixed()
  defp text_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case text_box_int_args_from_node(node, ints, runtime_model, eval_context) do
      {:ok, [font_id, x, y, w, h, alignment, overflow]} ->
        field_text = Map.get(node, "text") || Map.get(node, :text)

        if text = normalize_text_value(field_text) do
          {:ok, [font_id, x, y, w, h, alignment, overflow, text]}
        else
          case List.last(node_children(node)) do
            text_node when is_map(text_node) ->
              text =
                eval_view_text(text_node, runtime_model, eval_context) ||
                  text_node
                  |> Map.get("label")
                  |> normalize_text_value() ||
                  ""

              {:ok, [font_id, x, y, w, h, alignment, overflow, text]}

            nil ->
              :error
          end
        end

      :error ->
        :error
    end
  end

  defp text_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  defp text_box_int_args_from_node(node, ints, runtime_model, eval_context)
       when is_map(node) and is_list(ints) and is_map(runtime_model) and is_map(eval_context) do
    case require_ints(ints, 7) do
      {:ok, [font_id, x, y, w, h, alignment, overflow | _]} ->
        {:ok, [font_id, x, y, w, h, alignment, overflow]}

      :error ->
        case require_ints(ints, 5) do
          {:ok, [font_id, x, y, w, h | _]} ->
            alignment =
              text_alignment_value(Map.get(node, "text_align") || Map.get(node, :text_align))

            overflow =
              text_overflow_value(Map.get(node, "text_overflow") || Map.get(node, :text_overflow))

            {:ok, [font_id, x, y, w, h, alignment, overflow]}

          :error ->
            text_int_args_from_children(node_children(node), runtime_model, eval_context)
        end
    end
  end

  defp text_box_int_args_from_node(_node, _ints, _runtime_model, _eval_context), do: :error

  defp text_int_args_from_children(children, runtime_model, eval_context)
       when is_list(children) do
    case children do
      [font_node, options_node, bounds_node, _text_node] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             {:ok, [x, y, w, h]} <- rect_quad_from_node(bounds_node, runtime_model, eval_context),
             {:ok, [alignment, overflow]} <-
               text_options_from_node(options_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, alignment, overflow]}
        else
          _ -> :error
        end

      [font_node, x_node, y_node, w_node, h_node, alignment_node, overflow_node, _text_node | _] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             x when is_integer(x) <- eval_view_int(x_node, runtime_model, eval_context),
             y when is_integer(y) <- eval_view_int(y_node, runtime_model, eval_context),
             w when is_integer(w) <- eval_view_int(w_node, runtime_model, eval_context),
             h when is_integer(h) <- eval_view_int(h_node, runtime_model, eval_context),
             alignment when is_integer(alignment) <-
               eval_view_int(alignment_node, runtime_model, eval_context),
             overflow when is_integer(overflow) <-
               eval_view_int(overflow_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, alignment, overflow]}
        else
          _ -> :error
        end

      [font_node, x_node, y_node, w_node, h_node, _text_node | _] ->
        with font_id when is_integer(font_id) <-
               eval_view_font_id(font_node, runtime_model, eval_context),
             x when is_integer(x) <- eval_view_int(x_node, runtime_model, eval_context),
             y when is_integer(y) <- eval_view_int(y_node, runtime_model, eval_context),
             w when is_integer(w) <- eval_view_int(w_node, runtime_model, eval_context),
             h when is_integer(h) <- eval_view_int(h_node, runtime_model, eval_context) do
          {:ok, [font_id, x, y, w, h, 1, 0]}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp text_int_args_from_children(_children, _runtime_model, _eval_context), do: :error

  defp text_options_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")

    case type do
      "record" ->
        fields =
          node
          |> node_children()
          |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") == "field"))

        alignment =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "alignment"))
          |> field_value_int(runtime_model, eval_context)

        overflow =
          fields
          |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "overflow"))
          |> field_value_int(runtime_model, eval_context)

        if is_integer(alignment) and is_integer(overflow),
          do: {:ok, [alignment, overflow]},
          else: {:ok, [1, 0]}

      _ ->
        {:ok, [1, 0]}
    end
  end

  defp text_options_from_node(_node, _runtime_model, _eval_context), do: {:ok, [1, 0]}

  defp text_alignment_value("left"), do: 0
  defp text_alignment_value("right"), do: 2
  defp text_alignment_value(_), do: 1

  defp text_overflow_value("trailing_ellipsis"), do: 1
  defp text_overflow_value("fill"), do: 2
  defp text_overflow_value(_), do: 0

  defp text_alignment_name(0), do: "left"
  defp text_alignment_name(2), do: "right"
  defp text_alignment_name(_), do: "center"

  defp text_overflow_name(1), do: "trailing_ellipsis"
  defp text_overflow_name(2), do: "fill"
  defp text_overflow_name(_), do: "word_wrap"

  @spec view_tree_source(String.t() | nil) :: String.t()
  defp view_tree_source(message) when is_binary(message) and message != "",
    do: "step_derived_view_tree"

  defp view_tree_source(_), do: "parser_view_tree"

  @spec protocol_events(String.t(), [SemTypes.command_map()]) :: [map()]
  defp protocol_events(_source_root, commands) when is_list(commands) do
    commands
    |> Enum.filter(&protocol_command?/1)
    |> Enum.flat_map(&protocol_command_events/1)
  end

  defp protocol_events(_source_root, _commands), do: []

  @spec protocol_command?(SemTypes.command_map()) :: boolean()
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

  @spec package_followup_messages([SemTypes.command_map()], String.t()) :: [map()]
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

        task_command?(command) ->
          [
            %{
              "message" => map_value(command, :message) || "TaskPerformed",
              "message_value" => map_value(command, :message_value),
              "source_root" => source_root,
              "source" => "task_command",
              "package" => "elm/core",
              "command" => command
            }
          ]

        timer_command?(command) ->
          [
            %{
              "message" => map_value(command, :message) || "TimerFired",
              "message_value" => map_value(command, :message_value),
              "source_root" => source_root,
              "source" => "timer_command",
              "package" => map_value(command, :package) || "pebble/cmd",
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

  @spec resolve_timer_followup_messages([map()], map()) :: [map()]
  defp resolve_timer_followup_messages(followups, eval_context)
       when is_list(followups) and is_map(eval_context) do
    Enum.map(followups, &resolve_timer_followup_message(&1, eval_context))
  end

  defp resolve_timer_followup_messages(followups, _eval_context) when is_list(followups),
    do: followups

  defp resolve_timer_followup_messages(_followups, _eval_context), do: []

  @spec resolve_timer_followup_message(map(), map()) :: map()
  defp resolve_timer_followup_message(%{"source" => "timer_command"} = row, eval_context) do
    message_value = Map.get(row, "message_value")

    case resolve_followup_message_value(message_value, eval_context) do
      {message, resolved_value} ->
        row
        |> Map.put("message", message)
        |> Map.put("message_value", resolved_value)

      _ ->
        row
    end
  end

  defp resolve_timer_followup_message(row, _eval_context) when is_map(row), do: row
  defp resolve_timer_followup_message(row, _eval_context), do: row

  @spec resolve_followup_message_value(term(), map()) :: {String.t(), term()} | nil
  defp resolve_followup_message_value({:function_ref, name}, _eval_context) when is_binary(name),
    do: {name, %{"ctor" => name, "args" => []}}

  defp resolve_followup_message_value(%{"ctor" => ctor, "args" => args}, _eval_context)
       when is_binary(ctor) do
    {ctor, %{"ctor" => ctor, "args" => args || []}}
  end

  defp resolve_followup_message_value(%{ctor: ctor, args: args}, _eval_context)
       when is_binary(ctor) do
    {ctor, %{ctor: ctor, args: args || []}}
  end

  defp resolve_followup_message_value({tag, payload}, eval_context) when is_integer(tag) do
    case constructor_name_for_tag(tag, eval_context) do
      ctor when is_binary(ctor) ->
        {ctor, %{"ctor" => ctor, "args" => if(is_list(payload), do: payload, else: [])}}

      _ ->
        {"tag:#{tag}", {tag, payload}}
    end
  end

  defp resolve_followup_message_value(tag, eval_context) when is_integer(tag) do
    case constructor_name_for_tag(tag, eval_context) do
      ctor when is_binary(ctor) -> {ctor, %{"ctor" => ctor, "args" => []}}
      _ -> {"tag:#{tag}", tag}
    end
  end

  defp resolve_followup_message_value(_message_value, _eval_context), do: nil

  @spec constructor_name_for_tag(integer(), map()) :: String.t() | nil
  defp constructor_name_for_tag(tag, eval_context) when is_integer(tag) and is_map(eval_context) do
    candidates =
      eval_context
      |> Map.get(:constructor_tags, [])
      |> Enum.filter(fn entry ->
        entry_tag = Map.get(entry, :tag) || Map.get(entry, "tag")
        entry_tag == tag
      end)

    entry_module = Map.get(eval_context, :module) || Map.get(eval_context, "module")

    candidates
    |> Enum.find(fn entry ->
      union = Map.get(entry, :union) || Map.get(entry, "union")
      module = Map.get(entry, :module) || Map.get(entry, "module")
      update_module? = Map.get(entry, :update_module?) || Map.get(entry, "update_module?")

      update_module? == true and union == "Msg" and
        (not is_binary(entry_module) or module == entry_module)
    end)
    |> case do
      %{ctor: ctor} ->
        ctor

      %{"ctor" => ctor} ->
        ctor

      _ ->
        candidates
        |> Enum.find(fn entry ->
          Map.get(entry, :update_module?) || Map.get(entry, "update_module?") == true
        end)
        |> case do
          %{ctor: ctor} -> ctor
          %{"ctor" => ctor} -> ctor
          _ -> sole_constructor_name(candidates)
        end
    end
  end

  defp constructor_name_for_tag(_tag, _eval_context), do: nil

  @spec sole_constructor_name([map()]) :: String.t() | nil
  defp sole_constructor_name([%{ctor: ctor}]), do: ctor
  defp sole_constructor_name([%{"ctor" => ctor}]), do: ctor
  defp sole_constructor_name(_candidates), do: nil

  @spec http_command?(SemTypes.command_map()) :: boolean()
  defp http_command?(%{"kind" => "http"}), do: true
  defp http_command?(%{kind: "http"}), do: true
  defp http_command?(_), do: false

  @spec random_command?(SemTypes.command_map()) :: boolean()
  defp random_command?(%{"kind" => "cmd.random.generate"}), do: true
  defp random_command?(%{kind: "cmd.random.generate"}), do: true
  defp random_command?(_), do: false

  @spec storage_read_command?(SemTypes.command_map()) :: boolean()
  defp storage_read_command?(%{"kind" => "cmd.storage.read_" <> _rest}), do: true
  defp storage_read_command?(%{kind: "cmd.storage.read_" <> _rest}), do: true
  defp storage_read_command?(_), do: false

  @spec storage_write_command?(SemTypes.command_map()) :: boolean()
  defp storage_write_command?(%{"kind" => "cmd.storage.write_" <> _rest}), do: true
  defp storage_write_command?(%{kind: "cmd.storage.write_" <> _rest}), do: true
  defp storage_write_command?(_), do: false

  @spec storage_delete_command?(SemTypes.command_map()) :: boolean()
  defp storage_delete_command?(%{"kind" => "cmd.storage.delete"}), do: true
  defp storage_delete_command?(%{kind: "cmd.storage.delete"}), do: true
  defp storage_delete_command?(_), do: false

  @spec device_command?(SemTypes.command_map()) :: boolean()
  defp device_command?(%{"kind" => "cmd.device." <> _rest}), do: true
  defp device_command?(%{kind: "cmd.device." <> _rest}), do: true
  defp device_command?(_), do: false

  @spec task_command?(SemTypes.command_map()) :: boolean()
  defp task_command?(%{"kind" => "cmd.task." <> _rest}), do: true
  defp task_command?(%{kind: "cmd.task." <> _rest}), do: true
  defp task_command?(_), do: false

  @spec timer_command?(SemTypes.command_map()) :: boolean()
  defp timer_command?(%{"kind" => "cmd.timer.after"}), do: true
  defp timer_command?(%{kind: "cmd.timer.after"}), do: true
  defp timer_command?(_), do: false

  @spec unsupported_command?(SemTypes.command_map()) :: boolean()
  defp unsupported_command?(%{"kind" => "cmd.unsupported"}), do: true
  defp unsupported_command?(%{kind: "cmd.unsupported"}), do: true
  defp unsupported_command?(_), do: false

  @spec http_command_display(SemTypes.command_map()) :: String.t()
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

  @spec callable_display_name(EvalTypes.runtime_value()) :: String.t()
  defp callable_display_name({:function_ref, name}) when is_binary(name),
    do: unqualified_identifier(name)

  defp callable_display_name(name) when is_binary(name), do: unqualified_identifier(name)
  defp callable_display_name(_), do: ""

  @spec view_tree_node_count(map()) :: non_neg_integer()
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

  @spec stable_term_sha256(EvalTypes.runtime_value()) :: String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
