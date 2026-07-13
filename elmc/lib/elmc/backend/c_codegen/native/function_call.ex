defmodule Elmc.Backend.CCodegen.Native.FunctionCall do
  @moduledoc false

  alias Elmc.Backend.C.Lower.NativeReturn
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LayoutCoerceEmit
  alias Elmc.Backend.CCodegen.Native.ListIntReduce
  alias Elmc.Backend.CCodegen.Native.ListIntSearch
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.PlanNativeProjection
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type native_return_kind :: :native_int | :native_bool | :boxed

  @spec call?({String.t(), String.t()}, Types.compile_env()) :: boolean()
  def call?({module_name, name}, env) do
    env
    |> Map.get(:__program_decls__, %{})
    |> Map.get({module_name, name})
    |> case do
      nil -> false
      decl -> native_scalar_fn?(decl, module_name, Map.get(env, :__program_decls__, %{}))
    end
  end

  @spec compile(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile(module_name, name, args, env, counter) do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.fetch!({module_name, name})
    decl_map = Map.get(env, :__program_decls__, %{})
    return_kind = return_kind(decl, module_name, decl_map)

    case compile_native_result(module_name, name, args, env, counter, decl, decl_map, return_kind) do
      {code, ref, counter, :boxed} ->
        {code, ref, counter}

      {code, ref, counter, :native_int} ->
        {out, next} = RcRuntimeEmit.compile_result_slot(env, counter)

        {
          """
          #{code}
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_int", ref)}
          """,
          out,
          next
        }

      {code, ref, counter, :native_bool} ->
        {out, next} = RcRuntimeEmit.compile_result_slot(env, counter)

        {
          """
          #{code}
            #{RcRuntimeEmit.assign_call(env, out, "elmc_new_bool", ref)}
          """,
          out,
          next
        }
    end
  end

  @spec compile_scalar(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter(),
          :native_int | :native_bool
        ) :: Types.native_scalar_compile_result() | :error
  def compile_scalar(module_name, name, args, env, counter, expected_kind)
      when expected_kind in [:native_int, :native_bool] do
    decl = env |> Map.get(:__program_decls__, %{}) |> Map.get({module_name, name})
    decl_map = Map.get(env, :__program_decls__, %{})

    if decl && return_kind(decl, module_name, decl_map) == expected_kind do
      {code, ref, counter, ^expected_kind} =
        compile_native_result(
          module_name,
          name,
          args,
          env,
          counter,
          decl,
          decl_map,
          expected_kind
        )

      {code, ref, counter}
    else
      :error
    end
  end

  @spec compile_native_result(
          String.t(),
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter(),
          Types.function_declaration(),
          Types.function_decl_map(),
          native_return_kind()
        ) :: {String.t(), String.t(), Types.compile_counter(), native_return_kind()}
  defp compile_native_result(module_name, name, args, env, counter, decl, decl_map, return_kind) do
    arg_kinds = arg_kinds(decl, module_name, decl_map)
    borrow_args? = :borrow_arg in List.wrap(decl.ownership)
    arg_env = RcRuntimeEmit.strip_function_tail_scope(env)

    param_names =
      case decl do
        %{args: names} when is_list(names) -> names
        _ -> []
      end

    {arg_code, arg_refs, release_refs, counter} =
      args
      |> Enum.with_index()
      |> Enum.zip(arg_kinds)
      |> Enum.reduce({"", [], [], counter}, fn {{arg_expr, idx}, kind},
                                               {code_acc, refs_acc, releases_acc, c} ->
        case kind do
          :native_int ->
            {code, ref, c2} = Host.compile_native_int_expr(arg_expr, arg_env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :native_bool ->
            {code, ref, c2} = Host.compile_native_bool_expr(arg_expr, arg_env, c)
            {code_acc <> "\n  " <> code, refs_acc ++ [ref], releases_acc, c2}

          :boxed ->
            {code, ref, c2, passthrough?} =
              FunctionCallCompile.compile_call_operand_inner(arg_expr, arg_env, c,
                borrow_args?: borrow_args?
              )

            param = Enum.at(param_names, idx)

            {coerce_code, coerced_ref, c3, coerced_temp?} =
              LayoutCoerceEmit.coerce_call_operand(
                ref,
                arg_expr,
                module_name,
                name,
                param,
                arg_env,
                c2
              )

            final_ref = coerced_ref

            releases_acc =
              cond do
                coerced_temp? ->
                  releases_acc ++ [final_ref]

                passthrough? or EnvBindings.borrowed_arg_ref?(env, ref) ->
                  releases_acc

                borrow_args? ->
                  releases_acc ++ [final_ref]

                true ->
                  releases_acc ++ [final_ref]
              end

            {code_acc <> "\n  " <> code <> coerce_code, refs_acc ++ [final_ref], releases_acc, c3}
        end
      end)

    next = counter + 1

    {out, next} =
      if return_kind == :boxed and native_boxed_rc_abi?(decl, module_name, decl_map) and
           RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        native_rc_out_slot(env, next)
      else
        {native_call_out(return_kind, next), next}
      end

    c_name = Util.module_fn_name(module_name, name)
    arg_list = Enum.join(arg_refs, ", ")

    releases =
      release_refs
      |> Enum.map_join("\n  ", &ValueSlots.release_stmt/1)

    call_expr =
      cond do
        FunctionCallAbi.primary_lowered?(decl, module_name, decl_map) ->
          plan_primary_call_expr(
            c_name,
            decl,
            module_name,
            decl_map,
            arg_refs,
            return_kind,
            out,
            env
          )

        return_kind == :boxed and native_boxed_rc_abi?(decl, module_name, decl_map) ->
          native_boxed_rc_call_expr(c_name, arg_list, out, env)

        return_kind == :native_bool and native_bool_rc_abi?(decl, module_name, decl_map) ->
          native_bool_rc_call_expr(c_name, arg_list, out, env)

        true ->
          cond do
            return_kind in [:native_int, :native_bool] and
                not RcRequired.rc_required?(module_name, decl.name) and
                Host.function_return_type(decl.type) in ["Int", "Bool"] ->
              "#{native_call_decl(return_kind)}#{out} = #{c_name}(#{arg_list});"

            return_kind in [:native_int, :native_bool] and
                not RcRequired.rc_required?(module_name, decl.name) and
                NativeReturn.cached_kind({module_name, decl.name}) in [:native_int, :native_bool] ->
              "#{native_call_decl(return_kind)}#{out} = #{c_name}(#{arg_list});"

            true ->
              "#{native_call_decl(return_kind)}#{out} = #{c_name}_native(#{arg_list});"
          end
      end

    code = """
    #{arg_code}
      #{call_expr}
      #{releases}
    """

    {code, out, next, return_kind}
  end

  @spec native_args?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_args?(decl, module_name, decl_map) do
    decl
    |> arg_kinds(module_name, decl_map)
    |> Enum.any?(&(&1 in [:native_int, :native_bool]))
  end

  @spec native_scalar_fn?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_scalar_fn?(decl, module_name, decl_map) do
    expr = Map.get(decl, :expr)

    not Fusion.rc_native_fusion?(module_name, decl.name, expr, decl_map) and
      (native_args?(decl, module_name, decl_map) or
         ListIntSearch.recognized?(decl, module_name, decl_map) or
         match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) or
         native_scalar_return?(decl, module_name, decl_map))
  end

  # Bool/Int helpers over boxed records (for example Model -> Bool field checks) that
  # only need a native return when the body already lowers to native scalar code.
  @spec native_scalar_return?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_scalar_return?(%{type: type, expr: expr} = decl, module_name, decl_map)
      when is_binary(type) do
    env = analysis_env(decl, module_name, decl_map)

    case Host.function_return_type(type) do
      "Bool" -> Host.native_bool_expr?(expr || %{op: :int_literal, value: 0}, env)
      "Int" -> Host.native_int_expr?(expr || %{op: :int_literal, value: 0}, env)
      _ -> false
    end
  end

  def native_scalar_return?(_decl, _module_name, _decl_map), do: false

  @spec return_kind(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          native_return_kind()
  def return_kind(%{type: type, expr: expr} = decl, module_name, decl_map) when is_binary(type) do
    if native_scalar_fn?(decl, module_name, decl_map) do
      scalar_return_kind(decl, module_name, decl_map, type, expr)
    else
      :boxed
    end
  end

  def return_kind(_decl, _module_name, _decl_map), do: :boxed

  defp scalar_return_kind(decl, module_name, decl_map, type, expr) do
    env = analysis_env(decl, module_name, decl_map)

    case Host.function_return_type(type) do
      "Int" ->
        cond do
          Host.native_int_expr?(expr || %{op: :int_literal, value: 0}, env) ->
            :native_int

          ListIntSearch.recognized?(decl, module_name, decl_map) ->
            :native_int

          match?({:ok, _}, ListIntReduce.recognize(decl, module_name, decl_map)) ->
            :native_int

          true ->
            :boxed
        end

      "Bool" ->
        # Any Bool helper routed through native_scalar_fn compiles via Native.Bool
        # (including List.all bodies that fall back through Host and unbox).
        :native_bool

      _other ->
        :boxed
    end
  end

  @spec c_return_type(native_return_kind()) :: String.t()
  def c_return_type(:native_int), do: "elmc_int_t"
  def c_return_type(:native_bool), do: "bool"
  def c_return_type(:boxed), do: "ElmcValue *"

  @spec params(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          String.t()
  def params(decl, module_name, decl_map) do
    Host.c_arg_bindings(decl.args || [])
    |> Enum.zip(arg_kinds(decl, module_name, decl_map))
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> "const elmc_int_t #{c_arg}"
        :native_bool -> "const bool #{c_arg}"
        :boxed -> "ElmcValue * const #{c_arg}"
      end
    end)
  end

  @spec native_boxed_rc_abi?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_boxed_rc_abi?(decl, module_name, decl_map) do
    key = {module_name, decl.name}

    case Process.get(:elmc_native_boxed_rc_abi, %{}) do
      %{^key => rc?} when is_boolean(rc?) ->
        rc?

      _ ->
        native_boxed_rc_abi_default?(decl, module_name, decl_map)
    end
  end

  @spec native_boxed_rc_candidate?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_boxed_rc_candidate?(decl, module_name, decl_map) do
    native_boxed_rc_abi_default?(decl, module_name, decl_map)
  end

  defp native_boxed_rc_abi_default?(decl, module_name, decl_map) do
    expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}

    return_kind(decl, module_name, decl_map) == :boxed and
      (RcRequired.body_allocates?(expr) or
         (not match?(%{op: :list_literal}, expr) and
            not Tuple2CaseTable.recognized?(module_name, decl.name, expr)))
  end

  @spec native_bool_rc_abi?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_bool_rc_abi?(decl, module_name, decl_map) do
    key = {module_name, decl.name}

    case Process.get(:elmc_native_bool_rc_abi, %{}) do
      %{^key => rc?} when is_boolean(rc?) ->
        rc?

      _ ->
        native_bool_rc_abi_default?(decl, module_name, decl_map)
    end
  end

  @spec native_bool_rc_candidate?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def native_bool_rc_candidate?(decl, module_name, decl_map) do
    native_bool_rc_abi_default?(decl, module_name, decl_map)
  end

  defp native_bool_rc_abi_default?(decl, module_name, decl_map) do
    return_kind(decl, module_name, decl_map) == :native_bool and
      native_bool_body_needs_rc?(decl, module_name, decl_map)
  end

  defp native_bool_body_needs_rc?(decl, module_name, decl_map) do
    expr = Map.get(decl, :expr) || %{op: :int_literal, value: 0}

    RcRequired.body_allocates?(expr) or
      RcRequired.lambda_body_rc_required?(expr, module_name, decl_map)
  end

  @spec native_def_signature(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map(),
          native_return_kind()
        ) :: {String.t(), String.t()}
  def native_def_signature(decl, module_name, decl_map, return_kind) do
    boxed_rc_out? = return_kind == :boxed and native_boxed_rc_abi?(decl, module_name, decl_map)
    bool_rc_out? = return_kind == :native_bool and native_bool_rc_abi?(decl, module_name, decl_map)
    rc_out? = boxed_rc_out? or bool_rc_out?

    fn_arg_params = params(decl, module_name, decl_map)

    signature_params =
      cond do
        boxed_rc_out? ->
          RcRuntimeEmit.native_signature_suffix("ElmcValue **out", fn_arg_params)

        bool_rc_out? ->
          RcRuntimeEmit.native_signature_suffix("bool *out", fn_arg_params)

        true ->
          fn_arg_params
      end

    return_type =
      cond do
        rc_out? -> "RC"
        return_kind == :boxed -> "ElmcValue *"
        true -> c_return_type(return_kind)
      end

    {return_type, signature_params}
  end

  @spec arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [Types.native_function_arg_kind()]
  def arg_kinds(decl, module_name, decl_map) do
    case ListIntSearch.arg_kinds(decl, module_name, decl_map) do
      {:ok, kinds} -> kinds
      :error -> default_arg_kinds(decl, module_name, decl_map)
    end
  end

  @doc false
  @spec call_site_arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [Types.native_function_arg_kind()]
  def call_site_arg_kinds(decl, module_name, decl_map) do
    signature_kinds = signature_only_arg_kinds(decl)
    body_kinds = arg_kinds(decl, module_name, decl_map)

    if length(body_kinds) != length(signature_kinds) do
      cond do
        signature_kinds == [] and body_kinds != [] ->
          body_kinds

        true ->
          signature_kinds
      end
    else
      Enum.zip(signature_kinds, body_kinds)
      |> Enum.map(fn
        {:native_int, :boxed} -> :boxed
        {:native_bool, :boxed} -> :boxed
        {kind, _} -> kind
      end)
    end
  end

  @doc false
  @spec signature_has_native_args?(Types.function_declaration()) :: boolean()
  def signature_has_native_args?(decl) do
    signature_only_arg_kinds(decl)
    |> Enum.any?(&(&1 in [:native_int, :native_bool]))
  end

  @spec signature_arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          [Types.native_function_arg_kind()]
  def signature_arg_kinds(decl, module_name, decl_map) do
    case ListIntSearch.arg_kinds(decl, module_name, decl_map) do
      {:ok, kinds} -> kinds
      :error -> signature_only_arg_kinds(decl)
    end
  end

  defp default_arg_kinds(%{args: args, type: type, expr: expr}, module_name, decl_map)
       when is_list(args) and is_binary(type) do
    arg_types = Host.function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      case Enum.at(arg_types, index) |> Host.normalize_type_name() do
        "Int" ->
          if int_arg_safe?(arg, expr, module_name, decl_map) do
            :native_int
          else
            :boxed
          end

        "Bool" ->
          if bool_arg_safe?(arg, expr, module_name, decl_map) do
            :native_bool
          else
            :boxed
          end

        _other ->
          :boxed
      end
    end)
  end

  defp default_arg_kinds(%{args: args, type: type}, _module_name, _decl_map)
       when is_list(args) and is_binary(type) do
    signature_only_arg_kinds(%{args: args, type: type})
  end

  defp default_arg_kinds(%{args: args}, _module_name, _decl_map) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  defp default_arg_kinds(_decl, _module_name, _decl_map), do: []

  defp signature_only_arg_kinds(%{args: args, type: type})
       when is_list(args) and is_binary(type) do
    arg_types = Host.function_arg_types(type)

    args
    |> Enum.with_index()
    |> Enum.map(fn {_arg, index} ->
      case Enum.at(arg_types, index) |> Host.normalize_type_name() do
        "Int" -> :native_int
        "Bool" -> :native_bool
        _other -> :boxed
      end
    end)
  end

  defp signature_only_arg_kinds(%{args: args}) when is_list(args),
    do: Enum.map(args, fn _ -> :boxed end)

  defp signature_only_arg_kinds(_decl), do: []

  @spec int_arg_safe?(
          Types.binding_name(),
          Types.ir_expr() | nil,
          String.t(),
          Types.function_decl_map()
        ) :: boolean()
  defp int_arg_safe?(arg, expr, module_name, decl_map) do
    if Process.get(:elmc_skip_int_usage_recursion) do
      not Host.binding_used_in_lambda?(arg, expr)
    else
      usage =
        Host.native_int_usage(
          arg,
          expr || %{op: :int_literal, value: 0},
          module_name,
          decl_map
        )

      native_only? =
        usage.total == 0 or usage.boxed == 0 or usage.native_container >= usage.boxed

      lambda_safe? =
        not Host.binding_used_in_lambda?(arg, expr) or usage.boxed == 0

      native_only? and lambda_safe?
    end
  end

  @spec bool_arg_safe?(String.t(), Types.ir_expr() | nil, String.t(), Types.function_decl_map()) ::
          boolean()
  defp bool_arg_safe?(arg, expr, module_name, decl_map) do
    usage =
      Host.native_bool_usage(arg, expr || %{op: :int_literal, value: 0}, module_name, decl_map)

    (usage.total == 0 or usage.boxed == 0) and not Host.binding_used_in_lambda?(arg, expr)
  end

  defp native_call_out(:native_int, next), do: "native_call_#{next}"
  defp native_call_out(:native_bool, next), do: "native_bool_call_#{next}"
  defp native_call_out(:boxed, next), do: "tmp_#{next}"

  defp native_rc_out_slot(env, next) do
    case Map.get(env, :__into_out__) do
      into_out when is_binary(into_out) ->
        if RcRuntimeEmit.function_out_ref?(into_out) do
          alloc_native_rc_out(next)
        else
          if ValueSlots.owned_ref?(into_out) do
            ValueSlots.track(into_out)
            index = ValueSlots.owned_index(into_out) || 0
            {into_out, max(next, index + 1)}
          else
            alloc_native_rc_out(next)
          end
        end

      _ ->
        alloc_native_rc_out(next)
    end
  end

  defp alloc_native_rc_out(next) do
    {ref, index} = ValueSlots.alloc()
    {ref, max(next, index + 1)}
  end

  defp native_call_decl(:native_int), do: "const elmc_int_t "
  defp native_call_decl(:native_bool), do: "const bool "
  defp native_call_decl(:boxed), do: "ElmcValue *"

  defp native_boxed_rc_call_expr(c_name, arg_list, out, env) do
    caller_rc? =
      Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
        Map.get(env, :__native_rc_out__, false)

    out = ValueSlots.ensure_fresh_assign_target(out)
    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args(RcRuntimeEmit.allocator_out_arg(out), arg_list)})"

    if caller_rc? do
      unless RcRuntimeEmit.function_out_ref?(out), do: ValueSlots.track(out)

      prelude =
        cond do
          ValueSlots.owned_ref?(out) ->
            ValueSlots.owned_reassign_prefix(out)

          Map.get(env, :__into_out__) == out or RcRuntimeEmit.function_out_ref?(out) ->
            ""

          true ->
            ValueSlots.boxed_decl(out, "NULL") <> "\n"
        end

      stmt = prelude <> "Rc = #{call};\nCHECK_RC(Rc);"
      if ValueSlots.owned_ref?(out), do: ValueSlots.mark_written(out)
      stmt
    else
      """
      ElmcValue *#{out} = NULL;
      {
        RC __call_rc = #{call};
        if (__call_rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}_native", "native call failed");
          #{out} = NULL;
        }
      }
      """
    end
  end

  defp plan_primary_call_expr(c_name, decl, module_name, decl_map, arg_refs, return_kind, out, env) do
    caller_rc? =
      Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
        Map.get(env, :__native_rc_out__, false)

    {argv_setup, call_args} =
      if FunctionCallAbi.argv_abi?(decl, module_name, decl_map) do
        {setup, args_var, argc} = FunctionCallAbi.emit_argv_setup("native", arg_refs)
        {setup <> "\n  ", "#{args_var}, #{argc}"}
      else
        {"", Enum.join(arg_refs, ", ")}
      end

    rc_required? = RcRequired.rc_required?(module_name, decl.name)

    cond do
      return_kind == :native_int and
          NativeReturn.value_return?({module_name, decl.name}) ->
        argv_setup <> "const elmc_int_t #{out} = #{c_name}(#{call_args});"

      return_kind == :native_bool and
          NativeReturn.value_return?({module_name, decl.name}) ->
        argv_setup <> "const bool #{out} = #{c_name}(#{call_args});"

      return_kind == :native_int and
          not rc_required? and
          Host.function_return_type(decl.type) == "Int" ->
        argv_setup <> "const elmc_int_t #{out} = #{c_name}(#{call_args});"

      return_kind == :native_bool and
          not rc_required? and
          Host.function_return_type(decl.type) == "Bool" ->
        argv_setup <> "const bool #{out} = #{c_name}(#{call_args});"

      return_kind == :native_int and
          PlanNativeProjection.eligible?(decl, module_name, decl_map) ->
        native_decl = "elmc_int_t #{out} = 0;\n  "

        check =
          if caller_rc? do
            "Rc = #{c_name}_native(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}_native(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}_native", "native projection failed");
              }
            }
            """
          end

        argv_setup <> native_decl <> check

      return_kind == :native_bool and
          PlanNativeProjection.eligible?(decl, module_name, decl_map) ->
        native_decl = "bool #{out} = false;\n  "

        check =
          if caller_rc? do
            "Rc = #{c_name}_native(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}_native(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}_native", "native projection failed");
              }
            }
            """
          end

        argv_setup <> native_decl <> check

      return_kind == :native_int and
          rc_required? and
          FunctionCallAbi.direct_plan_call_abi?(decl, module_name, decl_map) and
          NativeReturn.cached_kind({module_name, decl.name}) == :native_int ->
        native_decl = "elmc_int_t #{out} = 0;\n  "

        check =
          if caller_rc? do
            "Rc = #{c_name}(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "native plan call failed");
              }
            }
            """
          end

        argv_setup <> native_decl <> check

      return_kind == :native_bool and
          rc_required? and
          FunctionCallAbi.direct_plan_call_abi?(decl, module_name, decl_map) and
          NativeReturn.cached_kind({module_name, decl.name}) == :native_bool ->
        native_decl = "bool #{out} = false;\n  "

        check =
          if caller_rc? do
            "Rc = #{c_name}(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});\nCHECK_RC(Rc);"
          else
            """
            {
              RC __call_rc = #{c_name}(#{RcRuntimeEmit.native_call_args("&" <> out, call_args)});
              if (__call_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}", "native plan call failed");
              }
            }
            """
          end

        argv_setup <> native_decl <> check

      return_kind == :native_int and
          not rc_required? and
          (NativeReturn.value_return?({module_name, decl.name}) or
             FunctionCallAbi.direct_plan_call_abi?(decl, module_name, decl_map)) ->
        argv_setup <> "const elmc_int_t #{out} = #{c_name}(#{call_args});"

      return_kind == :native_bool and
          not rc_required? and
          (NativeReturn.value_return?({module_name, decl.name}) or
             FunctionCallAbi.direct_plan_call_abi?(decl, module_name, decl_map)) ->
        argv_setup <> "const bool #{out} = #{c_name}(#{call_args});"

      return_kind == :native_int and
          not rc_required? and
          NativeReturn.cached_kind({module_name, decl.name}) == :native_int ->
        argv_setup <> "const elmc_int_t #{out} = #{c_name}(#{call_args});"

      return_kind == :native_bool and
          not rc_required? and
          NativeReturn.cached_kind({module_name, decl.name}) == :native_bool ->
        argv_setup <> "const bool #{out} = #{c_name}(#{call_args});"

      return_kind == :native_int ->
        boxed_var = "plan_primary_boxed_#{out}"

        call =
          if rc_required? do
            "Rc = #{c_name}(#{RcRuntimeEmit.allocator_out_arg(boxed_var)}, #{call_args});"
          else
            "#{boxed_var} = #{c_name}(#{call_args});"
          end

        extract = "const elmc_int_t #{out} = elmc_as_int(#{boxed_var});"
        release = "elmc_release(#{boxed_var});"

        boxed_decl =
          if rc_required?, do: "ElmcValue *#{boxed_var} = NULL;\n  ", else: ""

        check =
          if caller_rc? and rc_required? do
            "#{call}\nCHECK_RC(Rc);"
          else
            call
          end

        argv_setup <> boxed_decl <> check <> "\n  " <> extract <> "\n  " <> release

      return_kind == :native_bool ->
        boxed_var = "plan_primary_boxed_#{out}"

        check =
          if caller_rc? and rc_required? do
            "ElmcValue *#{boxed_var} = NULL;\n  Rc = #{c_name}(#{RcRuntimeEmit.allocator_out_arg(boxed_var)}, #{call_args});\nCHECK_RC(Rc);"
          else
            "ElmcValue *#{boxed_var} = #{c_name}(#{call_args});"
          end

        argv_setup <>
          check <>
          "\n  const bool #{out} = elmc_as_bool(#{boxed_var});\n  elmc_release(#{boxed_var});"

      return_kind == :boxed and rc_required? ->
        boxed_call =
          native_boxed_rc_call_expr(c_name, call_args, out, env)
          |> String.replace("#{c_name}_native(", "#{c_name}(")

        argv_setup <> boxed_call

      true ->
        rhs = "#{c_name}(#{call_args})"

        assign =
          if ValueSlots.owned_ref?(out) or RcRuntimeEmit.function_out_ref?(out) do
            ValueSlots.boxed_decl(out, rhs, env)
          else
            "#{native_call_decl(return_kind)}#{out} = #{rhs};"
          end

        argv_setup <> assign
    end
  end

  defp native_bool_rc_call_expr(c_name, arg_list, out, env) do
    caller_rc? =
      Map.get(env, :__rc_required__, false) or Map.get(env, :__rc_catch__, false) or
        Map.get(env, :__native_rc_out__, false)

    call = "#{c_name}_native(#{RcRuntimeEmit.native_call_args(RcRuntimeEmit.allocator_out_arg(out), arg_list)})"

    if caller_rc? do
      "bool #{out} = false;\nRc = #{call};\nCHECK_RC(Rc);"
    else
      """
      bool #{out} = false;
      {
        RC __call_rc = #{call};
        if (__call_rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(__call_rc, "#{c_name}_native", "native call failed");
          #{out} = false;
        }
      }
      """
    end
  end

  defp analysis_env(decl, module_name, decl_map) do
    callee_env(decl, module_name, decl_map)
    |> FunctionEmit.put_typed_arg_bindings(
      FunctionEmit.c_arg_bindings(decl.args || []),
      decl.type
    )
  end

  defp callee_env(decl, module_name, decl_map) do
    arg_names = decl.args || []
    arg_types = if is_binary(decl.type), do: Host.function_arg_types(decl.type), else: []

    Host.c_arg_bindings(arg_names)
    |> Enum.zip(arg_kinds(decl, module_name, decl_map))
    |> Enum.zip(arg_types)
    |> Enum.reduce(
      %{__module__: module_name, __program_decls__: decl_map, __function_name__: decl.name},
      fn {{{source_arg, c_arg, _index}, kind}, arg_type}, acc ->
        acc =
          case kind do
            :native_int -> EnvBindings.put_native_int_binding(acc, source_arg, c_arg)
            :native_bool -> EnvBindings.put_native_bool_binding(acc, source_arg, c_arg)
            :boxed -> Map.put(acc, source_arg, c_arg)
          end

        case {kind, Host.normalize_type_name(arg_type)} do
          {:native_int, _} -> acc
          {:native_bool, _} -> acc
          {_, "Int"} -> EnvBindings.put_boxed_int_binding(acc, source_arg, true)
          {_, "Bool"} -> EnvBindings.put_boxed_bool_binding(acc, source_arg, true)
          _ -> acc
        end
      end
    )
  end
end
