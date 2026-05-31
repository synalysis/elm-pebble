defmodule ElmExecutor.Runtime.SemanticExecutor.Execution do
  @moduledoc false
  @dialyzer :no_match

  alias ElmExecutor.Runtime.SemanticExecutor.View

  alias ElmExecutor.Runtime.CoreIRContract
  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

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
    core_ir = View.source_core_ir_fallback(artifact_core_ir, source, rel_path)

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

    entry_module =
      case map_value(request, :elm_executor_metadata) do
        %{"entry_module" => name} when is_binary(name) and name != "" -> name
        %{entry_module: name} when is_binary(name) and name != "" -> name
        _ -> source_module
      end

    eval_context =
      core_ir
      |> View.evaluator_context(entry_module)
      |> Map.merge(View.vector_resource_indices_context(request, current_model))
      |> Map.merge(View.bitmap_resource_indices_context(request, current_model))
      |> Map.merge(View.animation_resource_indices_context(request, current_model))
      |> Map.put(:launch_context, View.launch_context_from_model(current_model))
      |> Map.put(:elm_introspect, introspect)
      |> Map.put(:current_model, current_model)
    static_init_model = map_value(introspect, :init_model)

    base_runtime_model =
      case map_value(current_model, :runtime_model) do
        model when is_map(model) and map_size(model) > 0 ->
          model
          |> refresh_unresolved_fields_from_init(core_ir, eval_context, current_model)
          |> then(fn refreshed ->
            if unresolved_runtime_model?(refreshed) do
              evaluated_init_model(core_ir, eval_context, current_model) || refreshed
            else
              refreshed
            end
          end)

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
                 base_runtime_model,
                 current_model
               ) do
            {:ok, updated_model, commands, op, operation_source, key_provenance} ->
              updated =
                updated_model
                |> Map.put("last_message", branch_constructor_token(msg))
                |> Map.put("last_operation", branch_constructor_token(msg))

              {updated, "step_message", op, operation_source, key_provenance, commands}

            :error ->
              operation_source =
                if declared_message_constructor?(eval_context, msg),
                  do: "update_evaluation_failed",
                  else: "unmapped_message"

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

              {updated, "step_message", nil, operation_source, key_provenance, []}
          end

        _ ->
          init_commands = init_runtime_commands(eval_context, current_model)

          {base_runtime_model, "init_model", nil, "init_model", %{}, init_commands}
      end

    runtime_model = View.normalize_runtime_model_by_declared_type(runtime_model, eval_context)
    runtime_model_for_view = View.enrich_runtime_model_for_view(runtime_model, current_model)
    init_execution? = not (is_binary(message) and message != "")

    runtime_view_tree =
      View.derive_view_tree(
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
      |> View.derive_view_output(runtime_model_for_view, eval_context)
      |> View.annotate_view_output_sources(introspect)

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
  def map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  @spec generic_map_value(map(), String.t()) :: EvalTypes.runtime_value() | nil
  def generic_map_value(map, key) when is_map(map) and is_binary(key) do
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

  def generic_map_value(_map, _key), do: nil

  @spec list_count(EvalTypes.runtime_value()) :: non_neg_integer()
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

  @spec evaluate_update_from_core_ir(
          map(),
          map(),
          String.t(),
          SemTypes.message_value(),
          map(),
          map()
        ) ::
          {:ok, map(), [map()], atom() | nil, String.t(), map()} | :error
  defp evaluate_update_from_core_ir(
         core_ir,
         eval_context,
         message,
         message_value,
         runtime_model,
         current_model
       )
       when is_map(eval_context) and is_binary(message) and is_map(runtime_model) and is_map(current_model) do
    update_model =
      runtime_model_for_update_eval(runtime_model, core_ir, eval_context, current_model)

    with %{} = update_expr <- update_function_expr_from_core_ir(core_ir, eval_context),
         {:ok, msg_value} <- parse_message_value(message, message_value),
         msg_value = normalize_msg_for_core_ir(msg_value, eval_context),
         env = %{"msg" => msg_value, "model" => update_model},
         {:ok, result} <- evaluate_model_command_result(update_expr, env, eval_context),
         {:ok, result_model} <- update_result_model(result) do
      declared_fields = declared_model_fields(eval_context)

      model_updates =
        if declared_fields == [] do
          result_model
        else
          Map.take(result_model, declared_fields)
        end

      next_model = Map.merge(runtime_model, model_updates)
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
         _runtime_model,
         _current_model
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

  @spec refresh_unresolved_fields_from_init(map(), map(), map(), map()) :: map()
  defp refresh_unresolved_fields_from_init(model, core_ir, eval_context, current_model)
       when is_map(model) and is_map(eval_context) and is_map(current_model) do
    init_model =
      evaluated_init_model(core_ir, eval_context, current_model) ||
        introspect_init_model(eval_context)

    case init_model do
      %{} = resolved_init when map_size(resolved_init) > 0 ->
        Enum.reduce(model, model, fn {key, value}, acc ->
          if unresolved_runtime_value?(value) do
            case Map.get(resolved_init, key) || Map.get(resolved_init, to_string(key)) do
              replacement
              when is_map(replacement) or is_list(replacement) or is_number(replacement) or
                     is_boolean(replacement) or is_binary(replacement) ->
                Map.put(acc, key, replacement)

              _ ->
                acc
            end
          else
            acc
          end
        end)

      _ ->
        model
    end
  end

  defp refresh_unresolved_fields_from_init(model, _core_ir, _eval_context, _current_model), do: model

  @spec introspect_init_model(map()) :: map() | nil
  defp introspect_init_model(eval_context) when is_map(eval_context) do
    case Map.get(eval_context, :elm_introspect) do
      %{"init_model" => init} when is_map(init) -> init
      %{init_model: init} when is_map(init) -> init
      _ -> nil
    end
  end

  @spec runtime_model_for_update_eval(map(), map(), map(), map()) :: map()
  defp runtime_model_for_update_eval(runtime_model, core_ir, eval_context, current_model)
       when is_map(runtime_model) and is_map(eval_context) do
    runtime_model
    |> refresh_unresolved_fields_from_init(core_ir, eval_context, current_model)
    |> restrict_to_declared_model_fields(eval_context)
  end

  defp runtime_model_for_update_eval(runtime_model, _core_ir, _eval_context, _current_model),
    do: runtime_model

  @spec restrict_to_declared_model_fields(map(), map()) :: map()
  defp restrict_to_declared_model_fields(runtime_model, eval_context)
       when is_map(runtime_model) and is_map(eval_context) do
    case declared_model_fields(eval_context) do
      [] ->
        runtime_model

      fields ->
        runtime_model
        |> Map.take(fields)
        |> Enum.reject(fn {_key, value} -> unresolved_runtime_value?(value) end)
        |> Map.new()
    end
  end

  @spec declared_model_fields(map()) :: [String.t()]
  defp declared_model_fields(eval_context) when is_map(eval_context) do
    entry = entry_module_name(eval_context)
    aliases = Map.get(eval_context, :record_aliases, %{})

    case Map.get(aliases, {entry, "Model"}) do
      fields when is_list(fields) -> Enum.map(fields, &to_string/1)
      _ -> []
    end
  end

  @spec update_function_expr_from_core_ir(map(), map()) :: map() | nil
  defp update_function_expr_from_core_ir(core_ir, eval_context) when is_map(eval_context) do
    entry_module = entry_module_name(eval_context)

    core_ir
    |> core_ir_modules()
    |> update_expr_for_module(entry_module)
    |> case do
      %{} = expr ->
        expr

      _ ->
        core_ir
        |> core_ir_modules()
        |> Enum.find_value(&update_expr_in_module/1)
    end
  end

  defp update_function_expr_from_core_ir(_core_ir, _eval_context), do: nil

  @spec core_ir_modules(map()) :: [map()]
  defp core_ir_modules(%{modules: modules}) when is_list(modules), do: modules

  defp core_ir_modules(%{"modules" => modules}) when is_list(modules), do: modules

  defp core_ir_modules(_), do: []

  @spec update_expr_for_module([map()], String.t()) :: map() | nil
  defp update_expr_for_module(modules, entry_module) when is_list(modules) and is_binary(entry_module) do
    modules
    |> Enum.find(fn module ->
      to_string(generic_map_value(module, "name") || "") == entry_module
    end)
    |> update_expr_in_module()
  end

  @spec update_expr_in_module(map()) :: map() | nil
  defp update_expr_in_module(module) when is_map(module) do
    declarations = generic_map_value(module, "declarations") || []

    Enum.find_value(declarations, fn decl ->
      name = generic_map_value(decl, "name")
      kind = generic_map_value(decl, "kind")

      if name == "update" and (kind == "function" or kind == :function) do
        expr = generic_map_value(decl, "expr")
        if is_map(expr), do: expr, else: nil
      end
    end)
  end

  defp update_expr_in_module(_module), do: nil

  @spec entry_module_name(map()) :: String.t()
  def entry_module_name(eval_context) when is_map(eval_context) do
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
    launch_context = current_model |> map_value(:launch_context) |> View.normalize_launch_context()
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
    launch_context = current_model |> map_value(:launch_context) |> View.normalize_launch_context()
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

  @spec declared_message_constructor?(map(), String.t()) :: boolean()
  defp declared_message_constructor?(eval_context, message) when is_map(eval_context) and is_binary(message) do
    ctor = branch_constructor_token(message)

    eval_context
    |> Map.get(:elm_introspect)
    |> case do
      %{"msg_constructors" => constructors} when is_list(constructors) ->
        Enum.any?(constructors, fn known ->
          is_binary(known) and String.downcase(known) == String.downcase(ctor)
        end)

      %{msg_constructors: constructors} when is_list(constructors) ->
        Enum.any?(constructors, fn known ->
          is_binary(known) and String.downcase(known) == String.downcase(ctor)
        end)

      _ ->
        false
    end
  end

  defp declared_message_constructor?(_eval_context, _message), do: false

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

  @spec resolve_followup_message_value(EvalTypes.runtime_value(), map()) ::
          {String.t(), EvalTypes.runtime_value()} | nil
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
