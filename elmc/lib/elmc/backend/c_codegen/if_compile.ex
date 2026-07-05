defmodule Elmc.Backend.CCodegen.IfCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.HelperParams
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IntIfChain
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.PlatformStatic
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  defp if_result_out_binding(env, counter) do
    CaseCompile.result_out_binding(env, counter)
  end

  @spec compile(Types.ir_if_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(
        %{
          op: :if,
          cond: %{op: :int_literal, value: value},
          then_expr: then_expr,
          else_expr: else_expr
        },
        env,
        counter
      ) do
    Host.compile_expr(if(value != 0, do: then_expr, else: else_expr), env, counter)
  end

  def compile(
        %{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr},
        env,
        counter
      ) do
    compile_branches(cond_expr, then_expr, else_expr, env, counter)
  end

  @doc false
  @spec try_compile_int_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, Types.compile_result()} | :error
  def try_compile_int_branches(cond_expr, then_expr, else_expr, env, counter) do
    case int_if_chain_parse(cond_expr, then_expr, else_expr, env) do
      {:ok, subject, branches} ->
        {:ok, dispatch_int_if_chain(subject, branches, env, counter)}

      :error ->
        :error
    end
  end

  defp int_if_chain_parse(cond_expr, then_expr, else_expr, env) do
    case IntIfChain.parse_if_chain(cond_expr, then_expr, else_expr, env) do
      {:ok, _, _} = ok ->
        ok

      :error ->
        IntIfChain.parse_or_equality_if_chain(cond_expr, then_expr, else_expr, env)
    end
  end

  @spec compile_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_branches(cond_expr, then_expr, else_expr, env, counter) do
    case int_if_chain_parse(cond_expr, then_expr, else_expr, env) do
      {:ok, subject, branches} ->
        dispatch_int_if_chain(subject, branches, env, counter)

      :error ->
        compile_branches_fallback(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  defp dispatch_int_if_chain(subject, branches, env, counter) do
    if native_scalar_int_case?(env, branches) do
      NativeIntCase.compile_scalar(subject, branches, env, counter)
    else
      CaseCompile.dispatch(subject, branches, env, counter)
    end
  end

  defp native_scalar_int_case?(env, branches) do
    case Map.get(env, :__native_return_kind__) do
      :native_int -> true
      _ -> Enum.all?(branches, fn %{expr: expr} -> Host.native_int_expr?(expr, env) end)
    end
  end

  defp compile_branches_fallback(cond_expr, then_expr, else_expr, env, counter) do
    case PlatformStatic.platform_static_branch(cond_expr) do
      {macro, polarity} ->
        compile_platform_static_branches(macro, polarity, then_expr, else_expr, env, counter)

      nil ->
        compile_branches_fallback_runtime(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  defp compile_branches_fallback_runtime(cond_expr, then_expr, else_expr, env, counter) do
    cond do
      identical_branch_exprs?(then_expr, else_expr) ->
        Host.compile_expr(then_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and Host.native_int_expr?(then_expr, env) and
          Host.native_int_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_expr?(then_expr, env) and
          NativeString.boxed_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) and NativeString.boxed_non_null_expr?(then_expr, env) and
          NativeString.boxed_non_null_expr?(else_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      Host.native_bool_expr?(cond_expr, env) ->
        compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)

      true ->
        compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  @spec compile_native_bool_branches(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_native_bool_branches(cond_expr, then_expr, else_expr, env, counter) do
    case PlatformStatic.platform_static_branch(cond_expr) do
      {macro, polarity} ->
        compile_platform_static_branches(macro, polarity, then_expr, else_expr, env, counter)

      nil ->
        compile_runtime_native_bool_branches(cond_expr, then_expr, else_expr, env, counter)
    end
  end

  defp compile_runtime_native_bool_branches(cond_expr, then_expr, else_expr, env, counter) do
    cond_env = RcRuntimeEmit.strip_function_tail_scope(env)
    {cond_code, cond_ref, counter} = Host.compile_native_bool_expr(cond_expr, cond_env, counter)

    case cond_ref do
      "1" ->
        {branch_code, branch_ref, counter} =
          Host.compile_expr(then_expr, RecordCompile.fresh_subexpr_cache(env), counter)

        {cond_code <> branch_code, branch_ref, counter}

      "0" ->
        {branch_code, branch_ref, counter} =
          Host.compile_expr(else_expr, RecordCompile.fresh_subexpr_cache(env), counter)

        {cond_code <> branch_code, branch_ref, counter}

      _ ->
        {out, branch_counter, declare_out?} = if_result_out_binding(env, counter)
        branch_counter = CaseCompile.advance_counter_past_out(branch_counter, out, declare_out?)

        then_env = branch_env(env, out)
        else_env = branch_env(env, out)
        slots_before = ValueSlots.snapshot()

        {then_code, then_assignment, counter} =
          CaseCompile.branch_assignment(then_expr, out, then_env, branch_counter)

        ValueSlots.restore(slots_before)

        {else_code, else_assignment, counter} =
          CaseCompile.branch_assignment(else_expr, out, else_env, counter)

        then_body =
          maybe_extract_if_branch_helper(then_expr, then_env, out, then_code, then_assignment) <>
            "\n" <> ValueSlots.normalize_branch_result_slot(out)

        else_body =
          maybe_extract_if_branch_helper(else_expr, else_env, out, else_code, else_assignment) <>
            "\n" <> ValueSlots.normalize_branch_result_slot(out)

        code =
          Enum.join(
            [
              cond_code,
              CaseCompile.result_out_decl(out, declare_out?),
              "if (#{cond_ref}) {",
              format_if_branch_body(then_body),
              "} else {",
              format_if_branch_body(else_body),
              "}"
            ],
            "\n"
          )

        {code, out, counter}
    end
  end

  defp compile_platform_static_branches(macro, polarity, then_expr, else_expr, env, counter) do
    {out, branch_counter, declare_out?} = if_result_out_binding(env, counter)
    branch_counter = CaseCompile.advance_counter_past_out(branch_counter, out, declare_out?)

    then_env = branch_env(env, out)
    else_env = branch_env(env, out)
    slots_before = ValueSlots.snapshot()

    {then_code, then_assignment, counter} =
      CaseCompile.branch_assignment(then_expr, out, then_env, branch_counter)

    ValueSlots.restore(slots_before)

    {else_code, else_assignment, counter} =
      CaseCompile.branch_assignment(else_expr, out, else_env, counter)

    then_body =
      maybe_extract_if_branch_helper(then_expr, then_env, out, then_code, then_assignment)

    else_body =
      maybe_extract_if_branch_helper(else_expr, else_env, out, else_code, else_assignment)

    guard = PlatformStatic.ifdef_guard(macro, polarity)

    code =
      Enum.join(
        [
          CaseCompile.result_out_decl(out, declare_out?),
          "#if #{guard}",
          format_if_branch_body(then_body),
          "#else",
          format_if_branch_body(else_body),
          "#endif"
        ],
        "\n"
      )

    {code, out, counter}
  end

  @spec compile_boxed_cond(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defp compile_boxed_cond(cond_expr, then_expr, else_expr, env, counter) do
    cond_env =
      env
      |> RcRuntimeEmit.strip_function_tail_scope()
      |> Map.update(:__declared_outs__, MapSet.new(), fn declared ->
        out = Map.get(env, :__into_out__)

        if is_binary(out) do
          MapSet.delete(declared, out)
        else
          declared
        end
      end)

    {cond_code, cond_var, counter} = Host.compile_expr(cond_expr, cond_env, counter)

    case complementary_bool_branches(then_expr, else_expr) do
      polarity when polarity in [:cond_true, :cond_false] ->
        {out, counter, _declare?} = if_result_out_binding(env, counter)
        flag = if(polarity == :cond_true, do: "elmc_as_int(#{cond_var})", else: "(elmc_as_int(#{cond_var}) == 0)")

        assign =
          RcRuntimeEmit.assign_call(env, out, "elmc_new_bool", flag)
          |> String.trim()

        release =
          if cond_var != out, do: ValueSlots.release_stmt(cond_var), else: ""

        code =
          Enum.join([cond_code, assign, release], "\n")
          |> String.trim()

        {code, out, counter}

      _ ->
        compile_boxed_cond_branches(cond_code, cond_var, then_expr, else_expr, env, counter)
    end
  end

  defp compile_boxed_cond_branches(cond_code, cond_var, then_expr, else_expr, env, counter) do
    {out, branch_counter, declare_out?} = if_result_out_binding(env, counter)
    branch_counter = CaseCompile.advance_counter_past_out(branch_counter, out, declare_out?)

    then_env = branch_env(env, out)
    else_env = branch_env(env, out)
    parent_slots = ValueSlots.snapshot()

    {then_code, then_assignment, _counter} =
      with :ok <- ValueSlots.restore(parent_slots) do
        CaseCompile.branch_assignment(then_expr, out, then_env, branch_counter)
      end

    {else_code, else_assignment, counter} =
      with :ok <- ValueSlots.restore(parent_slots) do
        CaseCompile.branch_assignment(else_expr, out, else_env, branch_counter)
      end

    then_body =
      format_if_branch_body(
        Enum.join([then_code, then_assignment, ValueSlots.normalize_branch_result_slot(out)], "\n")
      )

    else_body =
      format_if_branch_body(
        Enum.join([else_code, else_assignment, ValueSlots.normalize_branch_result_slot(out)], "\n")
      )

    code =
      Enum.join(
        [
          cond_code,
          CaseCompile.result_out_decl(out, declare_out?),
          "if (elmc_as_int(#{cond_var}) != 0) {",
          then_body,
          "} else {",
          else_body,
          "}",
          if(cond_var != out, do: ValueSlots.release_stmt(cond_var), else: "")
        ],
        "\n"
      )

    {code, out, counter}
  end

  defp complementary_bool_branches(then_expr, else_expr) do
    case {bool_branch_polarity(then_expr), bool_branch_polarity(else_expr)} do
      {true, false} -> :cond_true
      {false, true} -> :cond_false
      _ -> nil
    end
  end

  defp bool_branch_polarity(%{op: :bool_literal, value: value}), do: value

  defp bool_branch_polarity(%{op: :int_literal, value: value}) when value in [0, 1],
    do: value == 1

  defp bool_branch_polarity(%{op: :constructor_call, target: target, args: []}) do
    case Host.special_value_from_target(target, []) do
      %{op: :bool_literal, value: value} -> value
      %{op: :int_literal, value: 1} -> true
      %{op: :int_literal, value: 0} -> false
      _ -> nil
    end
  end

  defp bool_branch_polarity(_), do: nil

  defp identical_branch_exprs?(left, right) do
    normalize_branch_expr(left) == normalize_branch_expr(right)
  end

  defp normalize_branch_expr(%{op: :var, name: name}), do: {:var, name}

  defp normalize_branch_expr(%{op: op, value: value}) when op in [:int_literal, :float_literal, :bool_literal, :string_literal],
    do: {op, value}

  defp normalize_branch_expr(%{op: op} = expr) when is_atom(op) do
    expr
    |> Map.drop([:meta, :loc, :span, :range, :source])
    |> Enum.sort()
    |> Enum.map(fn
      {key, value} when is_map(value) -> {key, normalize_branch_expr(value)}
      {key, value} when is_list(value) -> {key, Enum.map(value, &normalize_branch_expr/1)}
      pair -> pair
    end)
  end

  defp normalize_branch_expr(other), do: other

  defp branch_env(env, out) do
    ValueSlots.reset_function_out_written()

    env =
      env
      |> RecordCompile.fresh_subexpr_cache()
      |> Map.update(:__declared_outs__, MapSet.new([out]), &MapSet.put(&1, out))

    cond do
      RcRuntimeEmit.function_out_ref?(out) ->
        env
        |> RcRuntimeEmit.strip_function_tail_scope()
        |> Map.delete(:__branch_out__)

      ValueSlots.owned_ref?(out) ->
        env
        |> RcRuntimeEmit.strip_function_tail_scope()
        |> then(fn branch_env ->
          ValueSlots.set_result_slot_root(out)
          Map.put(branch_env, :__branch_out__, out)
        end)

      RcRuntimeEmit.function_tail_compile?(env) ->
        RcRuntimeEmit.strip_function_tail_scope(env)

      true ->
        env
    end
  end

  defp format_if_branch_body(body) do
    CSource.format_block(body, 4)
  end

  defp maybe_extract_if_branch_helper(expr, env, out, branch_code, assignment_code) do
    inline_body = format_if_branch_body(Enum.join([branch_code, assignment_code], "\n"))

    if extract_if_branch_helper?(env, inline_body) and not ValueSlots.owned_ref?(out) do
      case if_branch_helper_params(expr, env, branch_code, assignment_code) do
        {:ok, params} when params != [] ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_if_branch_helper_#{Util.safe_c_suffix(Map.get(env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(env, :__function_name__, "fn"))}_#{helper_id}"

          helper_param_decls = HelperParams.param_decls(params)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
            ElmcValue *#{out} = NULL;
          #{CSource.indent(branch_code, 2)}
            #{assignment_code}
            return #{out};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          call_args = HelperParams.call_args(params)

          """
              #{out} = #{helper_name}(#{call_args});
          """

        _ ->
          inline_body
      end
    else
      inline_body
    end
  end

  defp extract_if_branch_helper?(env, body) do
    RcRuntimeEmit.generic_helper_extraction_allowed?(env, body) and
      Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body) >= 70
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp if_branch_helper_params(expr, env, branch_code, assignment_code) do
    code = Enum.join([branch_code, assignment_code], "\n")

    ir_vars =
      expr
      |> external_vars()
      |> MapSet.to_list()

    code_vars = HelperParams.vars_in_c_source(code, env)

    (ir_vars ++ code_vars)
    |> Enum.uniq()
    |> Enum.sort()
    |> HelperParams.collect(env)
  end

  defp external_vars(expr), do: external_vars(expr, MapSet.new())

  defp external_vars(%{op: :var, name: name}, bound) when is_binary(name) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp external_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = external_vars(value_expr, bound)
    in_vars = external_vars(in_expr, MapSet.put(bound, EnvBindings.binding_key(name)))
    MapSet.union(value_vars, in_vars)
  end

  defp external_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound =
      Enum.reduce(args, bound, fn arg, acc -> MapSet.put(acc, EnvBindings.binding_key(arg)) end)

    external_vars(body, lambda_bound)
  end

  defp external_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) do
    key = EnvBindings.binding_key(arg)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
  end

  defp external_vars(expr, bound) when is_map(expr) do
    Enum.reduce(expr, MapSet.new(), fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        MapSet.union(acc, external_vars(value, bound))

      {_key, _value}, acc ->
        acc
    end)
  end

  defp external_vars(values, bound) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, external_vars(value, bound))
    end)
  end

  defp external_vars(_expr, _bound), do: MapSet.new()
end
