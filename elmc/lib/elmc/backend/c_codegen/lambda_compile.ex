defmodule Elmc.Backend.CCodegen.LambdaCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.VarAnalysis

  @spec compile([String.t()] | nil, Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  @spec compile(Types.ir_lambda_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :lambda, args: lambda_args, body: body}, env, counter),
    do: compile(lambda_args, body, env, counter)

  def compile(lambda_args, body, env, counter) do
    # Determine free variables captured from outer scope
    body_vars = VarAnalysis.used_vars(body)
    lambda_arg_set = MapSet.new(lambda_args || [])
    # Only capture variables that are actually resolvable in the current env.
    # Variables from case-branch bindings or other scopes that aren't in env
    # would generate undefined C identifiers, so we filter them out.
    env_keys = EnvBindings.env_resolvable_binding_keys(env)

    free_vars =
      body_vars
      |> MapSet.difference(lambda_arg_set)
      |> MapSet.intersection(env_keys)
      |> MapSet.to_list()
      |> Enum.sort()

    next = counter + 1
    lambda_arg_names = lambda_args || []

    lambda_signature =
      if free_vars == [] do
        {:lambda, lambda_arg_names, body}
      else
        nil
      end

    closure_fn_name =
      case lambda_signature && Map.get(Process.get(:elmc_lambda_defs, %{}), lambda_signature) do
        name when is_binary(name) ->
          name

        _ ->
          lambda_id = Process.get(:elmc_lambda_counter, 0) + 1
          Process.put(:elmc_lambda_counter, lambda_id)
          "elmc_lambda_#{lambda_id}"
      end

    lambda_arg_bindings = Host.c_arg_bindings(lambda_arg_names)
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    native_lambda_arg? = fn name ->
      usage = Host.native_int_usage(name, body, module_name, decl_map)
      usage.total > 0 and usage.boxed == 0 and not Host.binding_used_in_lambda?(name, body)
    end

    native_arg_names =
      lambda_arg_names
      |> Enum.filter(native_lambda_arg?)
      |> MapSet.new()

    native_free_vars =
      free_vars
      |> Enum.filter(native_lambda_arg?)
      |> MapSet.new()

    # Build arg bindings for the closure function body
    arg_bindings =
      lambda_arg_bindings
      |> Enum.map(fn {arg, c_arg, index} ->
        if MapSet.member?(native_arg_names, arg) do
          "const elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"
        else
          "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)
      |> Enum.join("\n  ")

    # Build capture bindings
    capture_bindings =
      free_vars
      |> Enum.with_index()
      |> Enum.map(fn {var_name, index} ->
        cond do
          MapSet.member?(native_free_vars, var_name) ->
            "const elmc_int_t #{var_name} = (capture_count > #{index} && captures[#{index}]) ? elmc_as_int(captures[#{index}]) : 0;"

          match?({:forward_ref, _}, Map.get(env, var_name)) ->
            "ElmcForwardRef *#{var_name}_letrec = (capture_count > #{index} && captures[#{index}] && captures[#{index}]->tag == ELMC_TAG_FORWARD_REF && captures[#{index}]->payload) ? *((ElmcForwardRef **)captures[#{index}]->payload) : NULL;"

          true ->
            "ElmcValue *#{var_name} = (capture_count > #{index}) ? captures[#{index}] : NULL;"
        end
      end)
      |> Enum.join("\n  ")

    bind_lambda_value = fn acc, name, c_ref, native_names ->
      cond do
        MapSet.member?(native_names, name) ->
          acc
          |> EnvBindings.put_native_int_binding(name, c_ref)
          |> EnvBindings.put_boxed_int_binding(name, false)

        match?({:forward_ref, _}, Map.get(env, name)) ->
          Map.put(acc, name, {:forward_ref_slot, "#{name}_letrec"})

        true ->
          Map.put(acc, name, c_ref)
      end
    end

    # Build the body in a clean environment with just args and captures as names
    # Propagate __module__ context so intra-module calls resolve correctly
    body_env =
      lambda_arg_bindings
      |> Enum.reduce(%{}, fn {arg, c_arg, _index}, acc ->
        bind_lambda_value.(acc, arg, c_arg, native_arg_names)
      end)
      |> then(fn acc ->
        Enum.reduce(free_vars, acc, fn name, acc ->
          bind_lambda_value.(acc, name, name, native_free_vars)
        end)
      end)
      |> Map.put(:__module__, Map.get(env, :__module__, "Main"))
      |> Map.put(:__function_name__, Map.get(env, :__function_name__))
      |> Map.put(:__function_arities__, EnvBindings.effective_function_arities(env))
      |> Map.put(:__program_decls__, EnvBindings.effective_program_decls(env))
      |> Map.put(:__direct_call_targets__, EnvBindings.effective_direct_call_targets(env))
      |> Map.put(:__borrowed_arg_refs__, Map.get(env, :__borrowed_arg_refs__, MapSet.new()))
      |> Map.put(:__inside_lambda__, true)

    {body_code, body_var, _body_counter} = Host.compile_expr(body, body_env, 0)

    unless lambda_signature && Map.has_key?(Process.get(:elmc_lambda_defs, %{}), lambda_signature) do
      # Hoist the closure function to file scope via process dictionary.
      closure_fn = """
      static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
        (void)args;
        (void)argc;
        (void)captures;
        (void)capture_count;
        #{arg_bindings}
        #{capture_bindings}
        #{body_code}
        return #{body_var};
      }
      """

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])

      if lambda_signature do
        lambda_defs = Process.get(:elmc_lambda_defs, %{})
        Process.put(:elmc_lambda_defs, Map.put(lambda_defs, lambda_signature, closure_fn_name))
      end
    end

    # Build the capture array and closure allocation at the call site
    capture_count = length(free_vars)

    capture_refs =
      free_vars
      |> Enum.map(&EnvBindings.capture_ref(env, &1))

    capture_list = Enum.join(capture_refs, ", ")
    out = "tmp_#{next}"

    {capture_array_code, capture_arg} =
      if capture_count > 0 do
        {"ElmcValue *cap_#{next}[#{capture_count}] = { #{capture_list} };", "cap_#{next}"}
      else
        {"", "NULL"}
      end

    code = """
      #{capture_array_code}
      ElmcValue *#{out} = elmc_closure_new(#{closure_fn_name}, #{length(lambda_arg_names)}, #{capture_count}, #{capture_arg});
    """

    {code, out, next}
  end
end
