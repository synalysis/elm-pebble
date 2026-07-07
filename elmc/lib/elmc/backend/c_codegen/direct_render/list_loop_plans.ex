defmodule Elmc.Backend.CCodegen.DirectRender.ListLoopPlans do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Release
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias ElmEx.IR.PipeChain

  @list_range_targets ~w(List.range Elm.Kernel.List.range)
  @list_map_targets ~w(List.map Elm.Kernel.List.map)
  @list_filter_targets ~w(List.filter Elm.Kernel.List.filter)
  @list_concat_targets ~w(List.concat Elm.Kernel.List.concat)

  @type filter_plan :: nil | {:mod_by_eq, pos_integer(), integer()} | {:native, String.t(), Types.ir_expr()}

  @type plan :: %{
          required(:range) => Types.ir_expr(),
          optional(:filter) => filter_plan(),
          optional(:map) => %{required(:param) => String.t(), required(:body) => Types.ir_expr()}
        }

  @spec fusion_plans?([plan()]) :: boolean()
  def fusion_plans?(plans) when is_list(plans) do
    length(plans) > 1 or
      Enum.any?(plans, fn plan ->
        Map.has_key?(plan, :map) or Map.has_key?(plan, :filter)
      end)
  end

  def fusion_plans?(_), do: false

  @spec pipeline_fragment?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def pipeline_fragment?(list_expr, env) do
    case analyze(list_expr, env) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @spec analyze(Types.ir_expr(), Types.compile_env()) :: {:ok, [plan()]} | :error
  def analyze(list_expr, env) do
    case resolve_expr(list_expr, env) do
      nil -> :error
      resolved -> analyze_resolved(resolved, env)
    end
  end

  @spec emit_map_loops(
          [plan()],
          Types.direct_emit_target(),
          String.t(),
          [String.t()],
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  def emit_map_loops(
        plans,
        {target_module, target_name, _prefix_args},
        prefix_code,
        prefix_vars,
        prefix_release_code,
        env,
        counter
      ) do
    c_name = Util.module_fn_name(target_module, target_name)
    decl_map = Map.get(env, :__program_decls__, %{})
    native_append? = map_native_append?(decl_map, {target_module, target_name, []})

    result =
      Enum.reduce_while(plans, {:ok, "", counter}, fn plan, {:ok, acc, c} ->
        case emit_single_plan_loop(plan, c_name, native_append?, prefix_vars, env, c) do
          {:ok, code, c2} -> {:cont, {:ok, acc <> code, c2}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, loops_code, counter} -> {:ok, prefix_code <> loops_code <> prefix_release_code, counter}
      :error -> :error
    end
  end

  defp resolve_expr(%{op: :var, name: name}, env) do
    case Map.get(env, name) do
      {:direct_fragment, fragment} -> resolve_expr(fragment, env)
      _ -> %{op: :var, name: name}
    end
  end

  defp resolve_expr(expr, _env) when is_map(expr), do: expr
  defp resolve_expr(_expr, _env), do: nil

  defp analyze_resolved(nil, _env), do: :error

  defp analyze_resolved(%{op: :pipe_chain, base: base, steps: steps}, env) when is_list(steps) do
    %{op: :pipe_chain, base: base, steps: steps}
    |> PipeChain.desugar()
    |> analyze_resolved(env)
  end

  defp analyze_resolved(%{op: :call, name: "__append__", args: [left, right]}, env) do
    with {:ok, left_plans} <- resolve_and_analyze(left, env),
         {:ok, right_plans} <- resolve_and_analyze(right, env) do
      {:ok, left_plans ++ right_plans}
    end
  end

  defp analyze_resolved(%{op: :qualified_call, target: target, args: args}, env) do
    normalized = Host.normalize_special_target(target)

    cond do
      normalized in @list_concat_targets ->
        analyze_resolved_concat(args, env)

      normalized in @list_map_targets ->
        analyze_map(args, env)

      normalized in @list_filter_targets ->
        analyze_filter(args, env)

      normalized in @list_range_targets ->
        analyze_range(args)

      true ->
        :error
    end
  end

  defp analyze_resolved(%{op: :call, name: "range", args: [first, last]}, _env) do
    {:ok, [%{range: %{op: :call, name: "range", args: [first, last]}}]}
  end

  defp analyze_resolved(%{op: :var, name: _name}, _env), do: :error
  defp analyze_resolved(_expr, _env), do: :error

  defp resolve_and_analyze(expr, env) do
    case resolve_expr(expr, env) do
      nil -> :error
      %{op: :var} -> :error
      resolved -> analyze_resolved(resolved, env)
    end
  end

  defp analyze_resolved_concat(args, env) when is_list(args) do
    Enum.reduce_while(args, {:ok, []}, fn expr, {:ok, acc} ->
      case resolve_and_analyze(expr, env) do
        {:ok, plans} -> {:cont, {:ok, acc ++ plans}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp analyze_map([fun, list], env) do
    with {:ok, base_plans} <- analyze_resolved(list, env),
         {:ok, param, body} <- map_lambda(fun) do
      plans =
        Enum.map(base_plans, fn plan ->
          Map.put(plan, :map, %{param: param, body: body})
        end)

      {:ok, plans}
    end
  end

  defp analyze_map(_args, _env), do: :error

  defp analyze_filter([pred, list], env) do
    with {:ok, [base | _] = plans} <- analyze_resolved(list, env),
         true <- length(plans) == 1,
         {:ok, param, body} <- filter_lambda(pred),
         filter when not is_nil(filter) <- filter_from_body(param, body) do
      {:ok, [Map.put(base, :filter, filter)]}
    else
      _ -> :error
    end
  end

  defp analyze_filter(_args, _env), do: :error

  defp analyze_range([first, last]) do
    range = %{op: :qualified_call, target: "List.range", args: [first, last]}
    {:ok, [%{range: range}]}
  end

  defp map_lambda(%{op: :lambda, args: [param], body: body}) when is_binary(param),
    do: {:ok, param, body}

  defp map_lambda(_), do: :error

  defp filter_lambda(%{op: :lambda, args: [param], body: body}) when is_binary(param),
    do: {:ok, param, body}

  defp filter_lambda(_), do: :error

  defp filter_from_body(param, body) do
    body = Host.unwrap_let_chain(body, %{}) |> elem(0)

    case mod_by_eq_filter(param, body) do
      {base, rem} when is_integer(base) and is_integer(rem) ->
        {:mod_by_eq, base, rem}

      nil ->
        body_env =
          %{}
          |> EnvBindings.put_native_int_binding(param, "direct_filter_item")
          |> EnvBindings.put_boxed_int_binding(param, false)

        if NativeBool.expr?(body, body_env) do
          {:native, param, body}
        end
    end
  end

  defp mod_by_eq_filter(param, body) do
    case eq_int_compare(body) do
      {mod_expr, rem} when is_integer(rem) ->
        case mod_by_base(mod_expr, param) do
          base when is_integer(base) -> {base, rem}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp eq_int_compare(%{op: :call, name: name, args: [left, right]})
       when name in ["__eq__", "==", "eq"] do
    case {literal_int(right), literal_int(left)} do
      {rem, _} when is_integer(rem) -> {left, rem}
      {_, rem} when is_integer(rem) -> {right, rem}
      _ -> nil
    end
  end

  defp eq_int_compare(%{op: :qualified_call, target: target, args: [left, right]}) do
    normalized = Host.normalize_special_target(target)

    if Host.qualified_builtin_operator_name(target) in ["__eq__", "==", "eq"] or
         normalized in ["Basics.eq", "Basics.=="] do
      case {literal_int(right), literal_int(left)} do
        {rem, _} when is_integer(rem) -> {left, rem}
        {_, rem} when is_integer(rem) -> {right, rem}
        _ -> nil
      end
    else
      nil
    end
  end

  defp eq_int_compare(_), do: nil

  defp mod_by_base(%{op: :qualified_call, target: target, args: [base, value]}, param) do
    case Host.normalize_special_target(target) do
      t when t in ["Basics.modBy", "modBy", "Elm.Kernel.modBy"] ->
        mod_by_base(%{op: :call, name: "modBy", args: [base, value]}, param)

      _ ->
        nil
    end
  end

  defp mod_by_base(%{op: :call, name: "modBy", args: [base, value]}, param) do
    case {literal_int(base), var_name(value)} do
      {base_int, ^param} when is_integer(base_int) -> base_int
      _ -> nil
    end
  end

  defp mod_by_base(
         %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, value]},
         param
       ),
       do: mod_by_base(%{op: :call, name: "modBy", args: [base, value]}, param)

  defp mod_by_base(_, _), do: nil

  defp literal_int(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp literal_int(%{op: :char_literal, value: value}) when is_integer(value), do: value
  defp literal_int(_), do: nil

  defp var_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp var_name(_), do: nil

  defp emit_single_plan_loop(plan, c_name, native_append?, prefix_vars, env, counter) do
    with {:ok, range_code, first_ref, last_ref, counter} <-
           Host.direct_range_bounds(plan.range, env, counter) do
      next = counter + 1
      item_var = "direct_item_i_#{next}"
      step_var = "direct_step_#{next}"

      {filter_code, counter} =
        emit_filter_guard(plan[:filter], item_var, first_ref, last_ref, next, env, counter)

      {item_code, item_ref, item_releases, counter} =
        emit_map_item(plan, item_var, env, counter)

      {call_code, _counter} =
        emit_append_call(
          c_name,
          native_append?,
          prefix_vars,
          item_ref,
          item_releases,
          next
        )

      loop_body = filter_code <> item_code <> call_code

      range_loop = """
      #{range_code}
        elmc_int_t #{step_var} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
        for (elmc_int_t #{item_var} = #{first_ref}; Rc == RC_SUCCESS; #{item_var} += #{step_var}) {
      #{CSource.indent(loop_body, 4)}
          if (#{item_var} == #{last_ref}) break;
        }
      """

      {:ok, range_loop, counter}
    end
  end

  defp emit_filter_guard(nil, _item_var, _first, _last, _next, _env, counter),
    do: {"", counter}

  defp emit_filter_guard({:mod_by_eq, base, rem}, item_var, _first_ref, last_ref, next, _env, counter) do
    mod_var = "direct_mod_#{next}"

    code = """
          elmc_int_t #{mod_var} = #{item_var} % #{base};
          if (#{mod_var} < 0) #{mod_var} += #{base};
          if (#{mod_var} != #{rem}) {
            if (#{item_var} == #{last_ref}) break;
            continue;
          }
    """

    {code, counter}
  end

  defp emit_filter_guard({:native, param, body}, item_var, _first_ref, last_ref, next, env, _counter) do
    body_env =
      env
      |> EnvBindings.put_native_int_binding(param, item_var)
      |> EnvBindings.put_boxed_int_binding(param, false)

    {body_code, body_ref, next_counter} = NativeBool.compile_expr(body, body_env, next)

    code = """
    #{body_code}
          if (!(#{body_ref})) {
            if (#{item_var} == #{last_ref}) break;
            continue;
          }
    """

    {code, next_counter}
  end

  defp emit_map_item(%{map: %{param: param, body: body}}, item_var, env, counter) do
    body_env =
      env
      |> EnvBindings.put_native_int_binding(param, item_var)
      |> EnvBindings.put_boxed_int_binding(param, false)

    {item_code, item_ref, counter} = Host.compile_expr(body, body_env, counter)
    releases = Release.release_var(item_ref, "        ")
    {item_code, item_ref, releases, counter}
  end

  defp emit_map_item(_plan, item_var, _env, counter) do
    item_ref = "direct_item_value_#{counter + 1}"
    next = counter + 1

    code =
      RcRuntimeEmit.check_rc_take(item_ref, "elmc_new_int", item_var, RcRuntimeEmit.rc_catch_env(%{}))

    {code, item_ref, Release.release_var(item_ref, "        "), next}
  end

  defp emit_append_call(c_name, true, prefix_refs, item_ref, item_releases, next) do
    arg_list = Enum.join(prefix_refs ++ [item_ref], ", ")

    code = """
          Rc = #{c_name}_commands_append_native(#{arg_list}, writer);
          #{item_releases}
          CHECK_RC(Rc);
    """

    {code, next}
  end

  defp emit_append_call(c_name, false, prefix_vars, item_ref, item_releases, next) do
    prefix_count = length(prefix_vars)

    prefix_bindings =
      prefix_vars
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {var, index} ->
        "      direct_call_args_#{next}[#{index}] = #{var};"
      end)

    code = """
         ElmcValue *direct_call_args_#{next}[#{max(prefix_count + 1, 1)}] = {0};
     #{prefix_bindings}
         direct_call_args_#{next}[#{prefix_count}] = #{item_ref};
         Rc = #{c_name}_commands_append(direct_call_args_#{next}, #{prefix_count + 1}, writer);
         #{item_releases}
         CHECK_RC(Rc);
    """

    {code, next}
  end

  defp map_native_append?(decl_map, target) do
    case target do
      {module_name, target_name, prefix_args} ->
        case Map.get(decl_map, {module_name, target_name}) do
          decl when is_map(decl) ->
            CommandDef.native_args?(decl) and prefix_args == []

          _ ->
            false
        end
    end
  end
end
