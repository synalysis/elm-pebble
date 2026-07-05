defmodule Elmc.Backend.CCodegen.DirectRender.RecordViewPeel do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type peel_binding :: Types.record_peel_binding()

  @spec peelable?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def peelable?(expr, env), do: match?({_helper_key, _helper_call}, peel_helper(expr, env, :emit))

  @spec inline_arg_binding(
          Types.binding_name(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: peel_binding() | nil
  def inline_arg_binding(_name, expr, env) do
    with {helper_key, helper_call} <- peel_helper(expr, env, :emit),
         source_ref when is_binary(source_ref) <- peel_source_ref(helper_call, env) do
      {:record_peel, source_ref, helper_key, helper_call}
    else
      _ -> nil
    end
  end

  @spec param_env_binding(
          Types.function_decl_key(),
          Types.binding_name(),
          String.t(),
          Types.function_decl_map()
        ) :: peel_binding() | nil
  def param_env_binding(target_key, param_name, c_arg, decl_map) do
    cache_key = {:record_view_peel, target_key, param_name, decl_peel_cache_tag(decl_map, target_key)}

    case Process.get(cache_key) do
      nil ->
        result = param_env_binding_impl(target_key, param_name, c_arg, decl_map)
        Process.put(cache_key, result || :none)
        result

      :none ->
        nil

      peel_binding ->
        peel_binding
    end
  end

  @spec reset_cache!() :: :ok
  def reset_cache! do
    for {key, _} <- Process.get(),
        is_tuple(key) and tuple_size(key) == 4 and elem(key, 0) == :record_view_peel do
      Process.delete(key)
    end

    :ok
  end

  defp decl_peel_cache_tag(decl_map, target_key) do
    case Map.get(decl_map, target_key) do
      %{expr: expr} when is_map(expr) -> :erlang.phash2(expr)
      _ -> :missing
    end
  end

  defp param_env_binding_impl(target_key, param_name, c_arg, decl_map) do
    with {:ok, %{args: arg_names}} <- Map.fetch(decl_map, target_key),
         param_index when is_integer(param_index) <- Enum.find_index(arg_names, &(&1 == param_name)),
         {:ok, helper_key} <- inherited_param_peel(target_key, param_index, decl_map, MapSet.new()),
         helper_call <- synthetic_helper_call(helper_key, decl_map) do
      {:record_peel, c_arg, helper_key, helper_call}
    else
      _ -> nil
    end
  end

  @spec peel_compile_env(
          Types.compile_env(),
          Types.function_decl_key(),
          Types.ir_expr(),
          String.t()
        ) :: Types.compile_env()
  def peel_compile_env(env, helper_key, helper_call, source_ref) do
    with [model_expr | _] <- Map.get(helper_call, :args, []),
         %{op: :var, name: model_name} <- model_expr,
         true <- is_binary(source_ref),
         decl_map <- Map.get(env, :__program_decls__, %{}),
         {:ok, %{type: type}} <- Map.fetch(decl_map, helper_key),
         [model_type | _] <- Host.function_arg_types(type) do
      env
      |> Map.put(model_name, source_ref)
      |> EnvBindings.put_var_type(model_name, model_type)
    else
      _ ->
        with [model_expr | _] <- Map.get(helper_call, :args, []),
             %{op: :var, name: model_name} <- model_expr,
             true <- is_binary(source_ref) do
          Map.put(env, model_name, source_ref)
        else
          _ -> env
        end
    end
  end

  @spec peel_env_for_field_access(Types.compile_env(), Types.ir_expr()) ::
          Types.compile_env()
  def peel_env_for_field_access(env, %{op: :var, name: name}) do
    case Map.get(env, name) || EnvBindings.lookup_binding(env, name) do
      {:record_peel, source_ref, helper_key, helper_call} ->
        peel_compile_env(env, helper_key, helper_call, source_ref)

      _ ->
        env
    end
  end

  def peel_env_for_field_access(env, _expr), do: env

  @spec field_expr(Types.compile_env(), Types.binding_name(), String.t()) ::
          Types.ir_expr() | nil
  def field_expr(env, name, field) do
    binding = Map.get(env, name) || EnvBindings.lookup_binding(env, name)

    case binding do
      {:record_peel, source_ref, helper_key, helper_call} ->
        peel_field_expr(helper_key, helper_call, field, env, source_ref)

      _ ->
        nil
    end
  end

  defp peel_field_expr(helper_key, helper_call, field, env, source_ref) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with {:ok, %{args: arg_names, expr: body}} <- Map.fetch(decl_map, helper_key),
         args <- Map.get(helper_call, :args, []),
         true <- length(arg_names) == length(args),
         substituted <- Host.substitute_expr(body, Map.new(Enum.zip(arg_names, args))),
         {body, let_bindings} <- Host.unwrap_let_chain(substituted, %{}),
         field_expr when not is_nil(field_expr) <- Expr.record_field_expr(body, field) do
      field_env = peel_field_env(env, helper_call, source_ref)
      resolve_peel_let_bindings(field_expr, let_bindings, field_env)
    else
      _ -> nil
    end
  end

  defp resolve_peel_let_bindings(expr, let_bindings, _env) when map_size(let_bindings) == 0,
    do: expr

  defp resolve_peel_let_bindings(%{op: :var, name: name} = var_expr, let_bindings, env)
       when is_binary(name) or is_atom(name) do
    key = EnvBindings.binding_key(name)

    case Map.fetch(let_bindings, key) do
      {:ok, bound} -> resolve_peel_let_bindings(bound, let_bindings, env)
      :error -> var_expr
    end
  end

  defp resolve_peel_let_bindings(expr, let_bindings, env) when is_map(expr) do
    expr
    |> Map.new(fn
      {key, value} when is_map(value) or is_list(value) ->
        {key, resolve_peel_let_bindings(value, let_bindings, env)}

      other ->
        other
    end)
  end

  defp resolve_peel_let_bindings(expr, _let_bindings, _env), do: expr

  @spec peeled_helpers_at_view(Types.ir_expr(), Types.compile_env()) :: [
          Types.function_decl_key()
        ]
  def peeled_helpers_at_view(view_expr, env) do
    entry_module = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    view_expr
    |> ui_node_inner()
    |> streaming_peel_helpers(entry_module, decl_map, env, MapSet.new(), 0)
  end

  defp streaming_peel_helpers(_expr, _module_name, _decl_map, _env, _seen, depth)
       when depth > 1,
       do: []

  defp streaming_peel_helpers(expr, module_name, decl_map, env, seen, depth) do
    direct =
      case peel_helper(expr, env, :shape) do
        {helper_key, _helper_call} -> [helper_key]
        nil -> []
      end

    call_helpers =
      expr
      |> call_sites(module_name)
      |> Enum.flat_map(fn %{target: target, args: args} ->
        arg_helpers =
          Enum.flat_map(args, fn arg ->
            case peel_helper(arg, env, :shape) do
              {helper_key, _helper_call} -> [helper_key]
              nil -> []
            end
          end)

        nested =
          if depth >= 1 or MapSet.member?(seen, target) or
               not streaming_glue_target?(target, decl_map) do
            []
          else
            case Map.fetch(decl_map, target) do
              {:ok, %{expr: callee_expr}} ->
                streaming_peel_helpers(
                  callee_expr,
                  elem(target, 0),
                  decl_map,
                  env,
                  MapSet.put(seen, target),
                  depth + 1
                )

              :error ->
                []
            end
          end

        arg_helpers ++ nested
      end)

    Enum.uniq(direct ++ call_helpers)
  end

  defp streaming_glue_target?(target_key, decl_map) do
    case Map.fetch(decl_map, target_key) do
      {:ok, %{type: type}} when is_binary(type) ->
        String.contains?(type, "List") and String.contains?(type, "RenderOp")

      _ ->
        false
    end
  end

  @spec inherited_param_peel(
          Types.function_decl_key(),
          non_neg_integer(),
          Types.function_decl_map(),
          MapSet.t()
        ) :: {:ok, Types.function_decl_key()} | :error
  defp inherited_param_peel(target_key, param_index, decl_map, visited) do
    visit_key = {target_key, param_index}

    if MapSet.member?(visited, visit_key) do
      :error
    else
      visited = MapSet.put(visited, visit_key)
      sites = call_sites_for(target_key, decl_map)

      if sites == [] do
        :error
      else
        sites
        |> Enum.reduce_while({:ok, nil}, fn site, {:ok, acc} ->
          case site_param_peel(site, param_index, decl_map, visited) do
            {:ok, helper_key} when acc in [nil, helper_key] -> {:cont, {:ok, helper_key}}
            _ -> {:halt, :error}
          end
        end)
        |> case do
          {:ok, nil} -> :error
          {:ok, helper_key} -> {:ok, helper_key}
          :error -> :error
        end
      end
    end
  end

  defp site_param_peel(%{caller: caller_key, args: args}, param_index, decl_map, visited) do
    with arg when not is_nil(arg) <- Enum.at(args, param_index),
         {:ok, caller_decl} <- Map.fetch(decl_map, caller_key),
         {:ok, caller_param_index} <- param_var_index(arg, caller_decl) do
      case inherited_param_peel(caller_key, caller_param_index, decl_map, visited) do
        {:ok, helper_key} ->
          {:ok, helper_key}

        :error ->
          call_sites_for(caller_key, decl_map)
          |> Enum.reduce_while({:ok, nil}, fn caller_site, {:ok, acc} ->
            case site_arg_peel(caller_site, caller_param_index, decl_map) do
              {:ok, helper_key} when acc in [nil, helper_key] -> {:cont, {:ok, helper_key}}
              _ -> {:halt, :error}
            end
          end)
          |> case do
            {:ok, nil} -> :error
            {:ok, helper_key} -> {:ok, helper_key}
            :error -> :error
          end
      end
    else
      _ -> :error
    end
  end

  defp site_arg_peel(%{args: args}, param_index, decl_map) do
    case Enum.at(args, param_index) do
      expr ->
        case peel_helper(expr, %{__program_decls__: decl_map}, :shape) do
          {helper_key, _helper_call} -> {:ok, helper_key}
          nil -> :error
        end
    end
  end

  defp param_var_index(%{op: :var, name: name}, %{args: arg_names}) when is_list(arg_names) do
    case Enum.find_index(arg_names, &(&1 == name)) do
      nil -> :error
      index -> {:ok, index}
    end
  end

  defp param_var_index(_expr, _decl), do: :error

  defp synthetic_helper_call(helper_key, decl_map) do
    with {:ok, helper_decl} <- Map.fetch(decl_map, helper_key),
         [helper_arg_name | _] <- helper_decl.args || [] do
      %{op: :call, name: elem(helper_key, 1), args: [%{op: :var, name: helper_arg_name}]}
    else
      _ ->
        {_module, name} = helper_key
        %{op: :call, name: name, args: [%{op: :var, name: "model"}]}
    end
  end

  defp peel_helper(expr, env, mode) do
    with helper_call when not is_nil(helper_call) <- helper_call_expr(expr),
         helper_key when not is_nil(helper_key) <- Expr.record_helper_target(helper_call, env),
         decl_map <- Map.get(env, :__program_decls__, %{}),
         {:ok, %{args: arg_names, expr: body}} <- Map.fetch(decl_map, helper_key),
         true <- record_literal_body?(body),
         args <- Map.get(helper_call, :args, []),
         true <- length(arg_names) == length(args),
         true <- Enum.all?(args, &peel_arg_expr?(&1, env, mode)) do
      {helper_key, helper_call}
    else
      _ -> nil
    end
  end

  defp helper_call_expr(%{op: :call, name: _name, args: _args} = expr), do: expr

  defp helper_call_expr(%{op: :qualified_call, target: target, args: args}) when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {_module, _name} -> %{op: :qualified_call, target: target, args: args}
      _ -> nil
    end
  end

  defp helper_call_expr(_expr), do: nil

  defp record_literal_body?(body) do
    {body, _} = Host.unwrap_let_chain(body, %{})

    case body do
      %{op: :record_literal, fields: fields} when is_list(fields) and fields != [] -> true
      _ -> false
    end
  end

  defp peel_arg_expr?(%{op: :var, name: _name}, _env, :shape), do: true
  defp peel_arg_expr?(%{op: :field_access}, _env, _mode), do: true

  defp peel_arg_expr?(%{op: :var, name: name}, env, :emit) when is_binary(name) or is_atom(name) do
    case EnvBindings.lookup_binding(env, name) do
      ref when is_binary(ref) -> true
      _ -> Map.has_key?(env, name)
    end
  end

  defp peel_arg_expr?(_expr, _env, _mode), do: false

  defp peel_source_ref(helper_call, env) do
    case Map.get(helper_call, :args, []) do
      [model_expr | _] -> peel_source_ref_expr(model_expr, env)
      _ -> nil
    end
  end

  defp peel_source_ref_expr(%{op: :var, name: name}, env) when is_binary(name) or is_atom(name) do
    case EnvBindings.lookup_binding(env, name) do
      ref when is_binary(ref) -> ref
      _ -> Map.get(env, name)
    end
  end

  defp peel_source_ref_expr(_expr, _env), do: nil

  defp peel_field_env(env, helper_call, source_ref) do
    with [model_expr | _] <- Map.get(helper_call, :args, []),
         %{op: :var, name: model_name} <- model_expr do
      ref = peel_source_ref_expr(model_expr, env) || source_ref

      if is_binary(ref) do
        Map.put(env, model_name, ref)
      else
        env
      end
    else
      _ -> env
    end
  end

  defp call_sites_for(target_key, decl_map) do
    decl_map
    |> Enum.flat_map(fn {{module_name, decl_name}, caller_decl} ->
      call_sites(caller_decl.expr, module_name)
      |> Enum.filter(&(&1.target == target_key))
      |> Enum.map(fn site -> Map.put(site, :caller, {module_name, decl_name}) end)
    end)
  end

  defp ui_node_inner(%{op: :qualified_call, target: "Pebble.Ui.toUiNode", args: [inner]}), do: inner
  defp ui_node_inner(expr), do: expr

  defp call_sites(expr, module_name) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: name, args: args} ->
          [%{target: {module_name, name}, args: args}]

        %{op: :qualified_call, target: target, args: args} ->
          case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
            nil -> []
            target_key -> [%{target: target_key, args: args}]
          end

        _ ->
          []
      end

    child =
      expr
      |> Map.values()
      |> Enum.flat_map(fn
        value when is_map(value) or is_list(value) -> call_sites(value, module_name)
        _ -> []
      end)

    own ++ child
  end

  defp call_sites(values, module_name) when is_list(values),
    do: Enum.flat_map(values, &call_sites(&1, module_name))

  defp call_sites(_value, _module_name), do: []
end
