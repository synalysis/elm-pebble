defmodule Elmc.Backend.CCodegen.LambdaCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots
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

    lambda_signature = {:lambda, lambda_arg_names, body, free_vars}

    closure_fn_name =
      case Map.get(Process.get(:elmc_lambda_defs, %{}), lambda_signature) do
        name when is_binary(name) ->
          name

        _ ->
          lambda_id = Process.get(:elmc_lambda_counter, 0) + 1
          Process.put(:elmc_lambda_counter, lambda_id)
          name = "elmc_lambda_#{lambda_id}"

          Process.put(
            :elmc_lambda_defs,
            Map.put(Process.get(:elmc_lambda_defs, %{}), lambda_signature, name)
          )

          name
      end

    lambda_arg_bindings = Host.c_arg_bindings(lambda_arg_names)
    module_name = Map.get(env, :__module__, "Main")
    decl_map = Map.get(env, :__program_decls__, %{})

    native_lambda_arg? = fn name ->
      usage = Host.native_int_usage(name, body, module_name, decl_map)

      usage.total > 0 and usage.boxed == 0 and usage.native_container == 0 and
        not Host.binding_used_in_lambda?(name, body)
    end

    native_arg_names =
      lambda_arg_names
      |> Enum.filter(native_lambda_arg?)
      |> MapSet.new()

    native_free_vars =
      free_vars
      |> Enum.filter(fn name ->
        native_lambda_arg?.(name) and not boxed_capture_in_env?(name, env)
      end)
      |> MapSet.new()

    # Build arg bindings for the closure function body
    arg_bindings =
      lambda_arg_bindings
      |> Enum.map(fn {arg, c_arg, index} ->
        binding =
          if MapSet.member?(native_arg_names, arg) do
            "const elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"
          else
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
          end

        if MapSet.member?(body_vars, arg) do
          binding
        else
          binding <> "\n  (void)#{c_arg};"
        end
      end)
      |> Enum.join("\n  ")

    # Build capture bindings
    capture_bindings =
      free_vars
      |> Enum.with_index()
      |> Enum.map(fn {var_name, index} ->
        binding =
          cond do
            MapSet.member?(native_free_vars, var_name) ->
              "const elmc_int_t #{var_name} = (capture_count > #{index} && captures[#{index}]) ? elmc_as_int(captures[#{index}]) : 0;"

            match?({:forward_ref, _}, Map.get(env, var_name)) ->
              "ElmcForwardRef *#{var_name}_letrec = (capture_count > #{index} && captures[#{index}] && captures[#{index}]->tag == ELMC_TAG_FORWARD_REF && captures[#{index}]->payload) ? *((ElmcForwardRef **)captures[#{index}]->payload) : NULL;"

            true ->
              "ElmcValue *#{var_name} = (capture_count > #{index}) ? captures[#{index}] : NULL;"
          end

        if MapSet.member?(body_vars, var_name) do
          binding
        else
          void_name =
            if match?({:forward_ref, _}, Map.get(env, var_name)),
              do: "#{var_name}_letrec",
              else: var_name

          binding <> "\n  (void)#{void_name};"
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
      |> propagate_lambda_metadata(env, lambda_arg_names ++ free_vars)
      |> Map.put(:__module__, Map.get(env, :__module__, "Main"))
      |> Map.put(:__function_name__, Map.get(env, :__function_name__))
      |> Map.put(:__function_arities__, EnvBindings.effective_function_arities(env))
      |> Map.put(:__program_decls__, EnvBindings.effective_program_decls(env))
      |> Map.put(:__direct_call_targets__, EnvBindings.effective_direct_call_targets(env))
      |> Map.put(:__borrowed_arg_refs__, Map.get(env, :__borrowed_arg_refs__, MapSet.new()))
      |> Map.put(:__inside_lambda__, true)

    rc_lambda? =
      Map.get(env, :__rc_catch__, false) and
        RcRequired.lambda_body_rc_required?(body, module_name, decl_map)

    body_env =
      if rc_lambda? do
        body_env
        |> Map.put(:__rc_required__, true)
        |> Map.put(:__rc_catch__, true)
        |> RcRuntimeEmit.function_tail_env()
      else
        body_env
      end

    parent_slots = Process.get(:elmc_value_slots, %{live: MapSet.new(), transferred: MapSet.new()})
    parent_borrowed = Process.get(:elmc_borrowed_field_refs, MapSet.new())

    if rc_lambda? do
      ValueSlots.reset(epilogue_lifo: true)
      RecordCompile.reset_borrowed_field_refs()
    end

    {body_code, body_var, _body_counter} = Host.compile_expr(body, body_env, 0)

    {owned_decls, body_code, failure_cleanup} =
      if rc_lambda? do
        if ValueSlots.owned_ref?(body_var) do
          :ok
        else
          if Regex.match?(~r/^tmp_\d+$/, body_var) do
            ValueSlots.track(body_var)
          end
        end

        decls = ValueSlots.owned_declaration()
        ValueSlots.set_emit_owned_epilogue(decls != "")

        cleanup = if decls != "", do: ValueSlots.failure_cleanup(), else: ""

        Process.put(:elmc_value_slots, parent_slots)
        Process.put(:elmc_borrowed_field_refs, parent_borrowed)
        {decls, body_code, cleanup}
      else
        {"", body_code, ""}
      end

    if not lambda_closure_emitted?(closure_fn_name) do
      closure_body = Enum.join([arg_bindings, capture_bindings, body_code], "\n  ")

      closure_void_casts =
        ["args", "argc", "captures", "capture_count"]
        |> Enum.reject(&closure_param_used?(&1, closure_body))
        |> Enum.map_join("\n  ", &"(void)#{&1};")

      # Hoist the closure function to file scope via process dictionary.
      closure_fn =
        if rc_lambda? do
          publish_out =
            cond do
              RcRuntimeEmit.function_out_ref?(body_var) ->
                ""

              ValueSlots.owned_ref?(body_var) ->
                "*out = #{body_var};\n    #{ValueSlots.null_assignment(body_var)}"

              true ->
                "*out = #{body_var};"
            end

          epilogue_block =
            if failure_cleanup == "" do
              ""
            else
              "\n    #{failure_cleanup}"
            end

          """
          static RC #{closure_fn_name}(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
            RC Rc = RC_SUCCESS;
            #{closure_void_casts}
            #{owned_decls}
            #{arg_bindings}
            #{capture_bindings}

            CATCH_BEGIN
              #{body_code}
              #{publish_out}
            CATCH_END;#{epilogue_block}
            return Rc;
          }
          """
        else
          identity_release = identity_arg_release_stmts(lambda_arg_bindings, body)

          """
          static ElmcValue *#{closure_fn_name}(ElmcValue **args, int argc, ElmcValue **captures, int capture_count) {
            #{closure_void_casts}
            #{arg_bindings}
            #{capture_bindings}
            #{body_code}
            #{identity_release}
            return #{body_var};
          }
          """
        end

      existing_lambdas = Process.get(:elmc_lambdas, [])
      Process.put(:elmc_lambdas, [closure_fn | existing_lambdas])

      emitted =
        Process.get(:elmc_lambda_emitted_names, MapSet.new())
        |> MapSet.put(closure_fn_name)

      Process.put(:elmc_lambda_emitted_names, emitted)
    end

    # Build the capture array and closure allocation at the call site
    capture_count = length(free_vars)

    {capture_setup, capture_refs, next} =
      free_vars
      |> Enum.reduce({[], [], next}, fn var, {stmts, refs, counter} ->
        ref = EnvBindings.capture_ref(env, var)

        case RcRuntimeEmit.parse_take_wrapper_call(ref) do
          {:ok, take_fn, call_args} ->
            cap_var = "cap_val_#{counter}"

            stmt =
              RcRuntimeEmit.take_wrapper_assign(cap_var, take_fn, call_args, env,
                return_on_fail?: not rc_lambda?,
                declare_out?: true
              )

            {[stmt | stmts], [cap_var | refs], counter + 1}

          :error ->
            {stmts, [ref | refs], counter}
        end
      end)
      |> then(fn {stmts, refs, counter} -> {Enum.reverse(stmts), Enum.reverse(refs), counter} end)

    out = "tmp_#{next}"
    capture_list = Enum.join(capture_refs, ", ")

    {capture_array_code, capture_arg} =
      if capture_count > 0 do
        {"ElmcValue *cap_#{next}[#{capture_count}] = { #{capture_list} };", "cap_#{next}"}
      else
        {"", "NULL"}
      end

    closure_args =
      "#{closure_fn_name}, #{length(lambda_arg_names)}, #{capture_count}, #{capture_arg}"

    closure_setup =
      if rc_lambda? do
        """
        #{ValueSlots.boxed_null_decl(out)}
        Rc = elmc_closure_new_rc(#{RcRuntimeEmit.allocator_out_arg(out)}, #{closure_args});
        CHECK_RC(Rc);
        """
      else
        RcRuntimeEmit.take_wrapper_assign(out, "elmc_closure_new", closure_args, env)
      end

    capture_setup_code =
      capture_setup
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    code = """
      #{capture_setup_code}
      #{capture_array_code}
      #{closure_setup}
    """

    {code, out, next}
  end

  defp lambda_closure_emitted?(closure_fn_name) when is_binary(closure_fn_name) do
    MapSet.member?(Process.get(:elmc_lambda_emitted_names, MapSet.new()), closure_fn_name) or
      Process.get(:elmc_lambdas, [])
      |> Enum.any?(fn defn -> String.contains?(defn, " #{closure_fn_name}(") end)
  end

  defp closure_param_used?(param, body) when is_binary(param) and is_binary(body) do
    Regex.match?(~r/(?:\W|^)#{Regex.escape(param)}(?:\W|$)/, body)
  end

  defp propagate_lambda_metadata(body_env, parent_env, names) when is_list(names) do
    keys = Enum.map(names, &EnvBindings.binding_key/1)

    var_types =
      parent_env
      |> Map.get(:__var_types__, %{})
      |> Map.take(keys)

    boxed_strings =
      Enum.reduce(names, MapSet.new(), fn name, acc ->
        key = EnvBindings.binding_key(name)

        cond do
          EnvBindings.boxed_string_binding?(parent_env, name) ->
            MapSet.put(acc, key)

          match?("String", normalize_lambda_type(Map.get(var_types, key))) ->
            MapSet.put(acc, key)

          true ->
            acc
        end
      end)

    body_env
    |> Map.put(:__var_types__, var_types)
    |> Map.put(:__boxed_string_bindings__, boxed_strings)
  end

  defp normalize_lambda_type(nil), do: nil

  defp normalize_lambda_type(type) when is_binary(type), do: Host.normalize_type_name(type)

  defp boxed_capture_in_env?(name, env) do
    case EnvBindings.lookup_binding(env, name) do
      ref when is_binary(ref) ->
        not EnvBindings.native_int_binding?(env, name) and
          not is_binary(EnvBindings.native_bool_binding(env, name)) and
          not is_binary(EnvBindings.native_float_binding(env, name))

      _ ->
        false
    end
  end

  defp identity_arg_release_stmts(lambda_arg_bindings, body) do
    case lambda_arg_bindings do
      [{arg, c_arg, 0}] ->
        if single_arg_identity_return?(body, arg) do
          "if (argc > 0 && #{c_arg}) elmc_release(#{c_arg});"
        else
          ""
        end

      _ ->
        ""
    end
  end

  defp single_arg_identity_return?(body, arg) do
    case body do
      %{op: :var, name: ^arg} ->
        true

      %{op: :call, name: name, args: [%{op: :var, name: ^arg}]} when name in ["identity"] ->
        true

      %{op: :qualified_call, target: "Basics.identity", args: [%{op: :var, name: ^arg}]} ->
        true

      _ ->
        false
    end
  end
end
