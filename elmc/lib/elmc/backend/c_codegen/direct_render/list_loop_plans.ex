defmodule Elmc.Backend.CCodegen.DirectRender.ListLoopPlans do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Commands
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Release
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr, as: CExpr
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
        case emit_single_plan_loop(
               plan,
               {target_module, target_name},
               c_name,
               native_append?,
               prefix_vars,
               env,
               c
             ) do
          {:ok, code, c2} -> {:cont, {:ok, acc <> code, c2}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, loops_code, counter} -> {:ok, prefix_code <> loops_code <> prefix_release_code, counter}
      :error -> :error
    end
  end

  @doc false
  @spec polar_tick_fusion_debug(plan(), Types.function_decl_key(), [String.t()], Types.compile_env()) ::
          {:ok, map()} | {:error, atom()}
  def polar_tick_fusion_debug(plan, {target_module, target_name} = target, prefix_vars, env) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with %{map: %{param: param, body: map_body}} <- plan do
      case Map.get(decl_map, {target_module, target_name}) do
        %{expr: body_expr} ->
          case parse_tick_spec_map(map_body, param, body_expr) do
            {:ok, tick} ->
              cond do
                not polar_scale_tick_target?({target_module, target_name}, decl_map) ->
                  {:error, :not_polar_scale_tick_target}

                polar_scale_tick_text_target(body_expr, Map.fetch!(tick, :label), target_module) == :error ->
                  {:error, :text_target}

                true ->
                  case tick_layout_coords(prefix_vars, target, env, decl_map) do
                    {:ok, cx_ref, cy_ref, outer_ref} ->
                      {:ok, %{tick: tick, cx_ref: cx_ref, cy_ref: cy_ref, outer_ref: outer_ref}}

                    :error ->
                      {:error, :layout_coords}
                  end
              end

            :error ->
              {:error, :parse_tick_spec}
          end

        _ ->
          {:error, :missing_decl}
      end
    else
      _ -> {:error, :plan_shape}
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

  defp emit_single_plan_loop(plan, target, c_name, native_append?, prefix_vars, env, counter) do
    with {:ok, range_code, first_ref, last_ref, counter} <-
           Host.direct_range_bounds(plan.range, env, counter) do
      next = counter + 1
      item_var = "direct_item_i_#{next}"
      step_var = "direct_step_#{next}"

      {filter_code, counter} =
        emit_filter_guard(plan[:filter], item_var, first_ref, last_ref, next, env, counter)

      case try_emit_polar_scale_tick_loop(
             plan,
             target,
             prefix_vars,
             filter_code,
             range_code,
             first_ref,
             last_ref,
             item_var,
             step_var,
             env,
             counter
           ) do
        {:ok, loop, counter} ->
          {:ok, loop, counter}

        :error ->
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
  end

  defp power_of_two?(n) when is_integer(n) and n > 0, do: Bitwise.band(n, n - 1) == 0

  defp emit_filter_guard(nil, _item_var, _first, _last, _next, _env, counter),
    do: {"", counter}

  defp emit_filter_guard({:mod_by_eq, base, rem}, item_var, _first_ref, last_ref, next, _env, counter) do
    if rem >= 0 and base > 0 and rem < base and power_of_two?(base) do
      mask = base - 1

      code = """
            if ((#{item_var} & #{mask}) != #{rem}) {
              if (#{item_var} == #{last_ref}) break;
              continue;
            }
      """

      {code, counter}
    else
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

  defp try_emit_polar_scale_tick_loop(
         plan,
         {target_module, target_name} = target,
         prefix_vars,
         filter_code,
         range_code,
         first_ref,
         last_ref,
         item_var,
         step_var,
         env,
         counter
       ) do
    decl_map = Map.get(env, :__program_decls__, %{})

    with %{map: %{param: param, body: map_body}} <- plan,
         %{expr: body_expr} <- Map.get(decl_map, {target_module, target_name}),
         {:ok, tick} <- parse_tick_spec_map(map_body, param, body_expr),
         true <- polar_scale_tick_target?({target_module, target_name}, decl_map),
         {:ok, text_target} <- polar_scale_tick_text_target(body_expr, tick.label, target_module),
         {:ok, cx_ref, cy_ref, outer_ref} <-
           tick_layout_coords(prefix_vars, target, env, decl_map) do
      next = counter + 1
      minute_expr = tick_minute_c_expr(tick, item_var)
      outer_radius_extra = Map.fetch!(tick, :outer_extra)
      text_c_name =
        case text_target do
          {mod, name} -> Util.module_fn_name(mod, name)
          _ -> nil
        end

      label_radius_extra = Map.get(tick, :label_radius_extra, 14)
      {box_dx, box_dy, box_w, box_h} = Map.get(tick, :label_box, {9, 14, 18, 12})

      label_branch =
        case Map.fetch!(tick, :label) do
          :nothing ->
            {:ok, polar_tick_line_emit(next)}

          {:from_int, scale} ->
            if is_binary(text_c_name) do
              {:ok,
               polar_tick_labeled_emit(
                 scale,
                 item_var,
                 text_c_name,
                 cx_ref,
                 cy_ref,
                 outer_ref,
                 label_radius_extra,
                 {box_dx, box_dy, box_w, box_h},
                 next
               )}
            else
              :error
            end
        end

    with {:ok, label_branch} <- label_branch do
      loop_body = """
      #{filter_code}
            const elmc_int_t direct_tick_minute_#{next} = #{minute_expr};
            const elmc_int_t direct_tick_angle_#{next} = elmc_angle_from_minute(direct_tick_minute_#{next});
            const elmc_int_t direct_tick_inner_x_#{next} = elmc_polar_point_x(#{cx_ref}, #{cy_ref}, #{outer_ref}, direct_tick_angle_#{next});
            const elmc_int_t direct_tick_inner_y_#{next} = elmc_polar_point_y(#{cx_ref}, #{cy_ref}, #{outer_ref}, direct_tick_angle_#{next});
            const elmc_int_t direct_tick_outer_x_#{next} = elmc_polar_point_x(#{cx_ref}, #{cy_ref}, (#{outer_ref} + #{outer_radius_extra}), direct_tick_angle_#{next});
            const elmc_int_t direct_tick_outer_y_#{next} = elmc_polar_point_y(#{cx_ref}, #{cy_ref}, (#{outer_ref} + #{outer_radius_extra}), direct_tick_angle_#{next});
      #{label_branch}
      """

      range_loop = """
      #{range_code}
        elmc_int_t #{step_var} = (#{first_ref} <= #{last_ref}) ? 1 : -1;
        for (elmc_int_t #{item_var} = #{first_ref}; Rc == RC_SUCCESS; #{item_var} += #{step_var}) {
      #{CSource.indent(loop_body, 4)}
          if (#{item_var} == #{last_ref}) break;
        }
      """

      {:ok, range_loop, counter}
    else
      _ -> :error
    end
    else
      _ -> :error
    end
  end

  defp parse_tick_spec_map(%{op: :record_literal, fields: fields}, param, body_expr)
       when is_list(fields) do
    field_map =
      Map.new(fields, fn
        %{name: name, expr: expr} when is_atom(name) -> {Atom.to_string(name), expr}
        %{name: name, expr: expr} when is_binary(name) -> {name, expr}
      end)

    with {:ok, tick} <- parse_tick_spec_fields(field_map, param, body_expr) do
      {:ok, tick}
    else
      _ -> parse_tick_spec_fields_by_position(fields, param, body_expr)
    end
  end

  defp parse_tick_spec_map(_, _, _), do: :error

  defp parse_tick_spec_fields(field_map, param, body_expr) do
    with {:ok, minute_scale} <- tick_minute_scale(field_map["minute"], param),
         outer_extra when is_integer(outer_extra) <- literal_int(field_map["outerExtra"]),
         {:ok, label} <- tick_label_kind(field_map["label"], param) do
      label_meta =
        case label do
          {:from_int, _} -> parse_tick_label_layout(body_expr)
          _ -> %{}
        end

      {:ok,
       Map.merge(
         %{minute_scale: minute_scale, outer_extra: outer_extra, label: label},
         label_meta
       )}
    end
  end

  defp parse_tick_spec_fields_by_position(fields, param, body_expr) when is_list(fields) do
    case fields do
      [%{expr: minute}, %{expr: outer_extra_expr}, %{expr: label}] ->
        with {:ok, minute_scale} <- tick_minute_scale(minute, param),
             outer_extra when is_integer(outer_extra) <- literal_int(outer_extra_expr),
             {:ok, label_kind} <- tick_label_kind(label, param) do
          label_meta =
            case label_kind do
              {:from_int, _} -> parse_tick_label_layout(body_expr)
              _ -> %{}
            end

          {:ok,
           Map.merge(
             %{minute_scale: minute_scale, outer_extra: outer_extra, label: label_kind},
             label_meta
           )}
        end

      _ ->
        :error
    end
  end

  defp tick_minute_scale(expr, param) do
    case mul_of_param(expr, param) do
      scale when is_integer(scale) -> {:ok, scale}
      _ -> :error
    end
  end

  defp mul_of_param(
         %{op: :call, name: name, args: [left, right]},
         param
       )
       when name in ["__mul__", "*"] do
    case {var_name(left), literal_int(right), var_name(right), literal_int(left)} do
      {^param, scale, _, _} when is_integer(scale) -> scale
      {_, _, ^param, scale} when is_integer(scale) -> scale
      _ -> nil
    end
  end

  defp mul_of_param(
         %{op: :qualified_call, target: target, args: [left, right]},
         param
       ) do
    if Host.qualified_builtin_operator_name(target) in ["__mul__", "*"] do
      mul_of_param(%{op: :call, name: "__mul__", args: [left, right]}, param)
    else
      nil
    end
  end

  defp mul_of_param(%{op: :var, name: name}, param) do
    if var_name(%{op: :var, name: name}) == param, do: 1, else: nil
  end

  defp mul_of_param(_, _), do: nil

  defp tick_label_kind(expr, param) do
    case expr do
      %{op: :tuple2, left: %{union_ctor: ctor}, right: inner} when is_binary(ctor) ->
        tick_union_ctor_just_label_kind(ctor, inner, param)

      %{op: :int_literal, union_ctor: ctor} when is_binary(ctor) ->
        tick_union_ctor_label_kind(ctor)

      %{op: :qualified_call, target: target, args: []} ->
        case Host.normalize_special_target(target) do
          t when t in ["Maybe.Nothing", "Basics.Nothing"] -> {:ok, :nothing}
          _ -> :error
        end

      %{op: :constructor_call, target: target, args: []} ->
        case Host.normalize_special_target(target) do
          t when t in ["Maybe.Nothing", "Basics.Nothing", "Nothing"] -> {:ok, :nothing}
          _ -> :error
        end

      %{op: :union_constructor, name: "Nothing"} ->
        {:ok, :nothing}

      %{op: :qualified_call, target: target, args: [inner]} ->
        case Host.normalize_special_target(target) do
          "Maybe.Just" ->
            case string_from_int_scale(inner, param) do
              scale when is_integer(scale) -> {:ok, {:from_int, scale}}
              _ -> :error
            end

          _ ->
            :error
        end

      %{op: :constructor_call, target: target, args: [inner]} ->
        case Host.normalize_special_target(target) do
          t when t in ["Maybe.Just", "Just"] ->
            case string_from_int_scale(inner, param) do
              scale when is_integer(scale) -> {:ok, {:from_int, scale}}
              _ -> :error
            end

          _ ->
            :error
        end

      %{op: :union_constructor, name: "Just", args: [inner]} ->
        case string_from_int_scale(inner, param) do
          scale when is_integer(scale) -> {:ok, {:from_int, scale}}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp tick_union_ctor_label_kind(ctor) do
    case Host.normalize_special_target(ctor) do
      t when t in ["Maybe.Nothing", "Basics.Nothing", "Nothing"] ->
        {:ok, :nothing}

      _ ->
        :error
    end
  end

  defp tick_union_ctor_just_label_kind(ctor, inner, param) do
    case Host.normalize_special_target(ctor) do
      t when t in ["Maybe.Just", "Just"] ->
        case string_from_int_scale(inner, param) do
          scale when is_integer(scale) -> {:ok, {:from_int, scale}}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp string_from_int_scale(expr, param) do
    case expr do
      %{op: :qualified_call, target: target, args: [value]} ->
        if Host.normalize_special_target(target) in ["String.fromInt", "Basics.fromInt"] do
          mul_of_param(value, param)
        end

      %{op: :call, name: "fromInt", args: [value]} ->
        mul_of_param(value, param)

      %{op: :runtime_call, function: fun, args: [value]}
      when fun in ["elmc_string_from_int", "elmc_string_fromInt"] ->
        mul_of_param(value, param)

      _ ->
        nil
    end
  end

  defp tick_minute_c_expr(%{minute_scale: 1}, item_var), do: item_var
  defp tick_minute_c_expr(%{minute_scale: scale}, item_var), do: "(#{item_var} * #{scale})"

  defp tick_layout_coords(prefix_vars, {target_module, target_name} = target, env, decl_map) do
    case prefix_vars do
      [layout_ref | _] ->
        cx = layout_field_ref(layout_ref, "cx", target, decl_map, env)
        cy = layout_field_ref(layout_ref, "cy", target, decl_map, env)
        outer = layout_field_ref(layout_ref, "outerRadius", target, decl_map, env)
        if cx && cy && outer, do: {:ok, cx, cy, outer}, else: :error

      [] ->
        with {:ok, layout_name} <- tick_layout_param_name(target_module, target_name, decl_map),
             {:ok, cx, cy, outer} <- tick_layout_coords_from_env(layout_name, env) do
          {:ok, cx, cy, outer}
        end
    end
  end

  defp tick_layout_coords_from_env(layout_name, env) do
    cond do
      match?({:native_record, _fields}, Map.get(env, layout_name)) ->
        {:native_record, fields} = Map.get(env, layout_name)

        with {:ok, cx} <- Map.fetch(fields, "cx"),
             {:ok, cy} <- Map.fetch(fields, "cy"),
             {:ok, outer} <- Map.fetch(fields, "outerRadius") do
          {:ok, cx, cy, outer}
        end

      true ->
        case EnvBindings.let_value_expr(env, layout_name) do
          %{op: :record_literal, fields: fields} -> layout_literal_coord_refs(fields)
          _ -> :error
        end
    end
  end

  defp layout_literal_coord_refs(fields) when is_list(fields) do
    field_map =
      Map.new(fields, fn
        %{name: name, expr: expr} when is_atom(name) -> {Atom.to_string(name), expr}
        %{name: name, expr: expr} when is_binary(name) -> {name, expr}
      end)

    with cx when not is_nil(cx) <- literal_int(field_map["cx"]),
         cy when not is_nil(cy) <- literal_int(field_map["cy"]),
         outer when not is_nil(outer) <- literal_int(field_map["outerRadius"]) do
      {:ok, Integer.to_string(cx), Integer.to_string(cy), Integer.to_string(outer)}
    else
      _ -> :error
    end
  end

  defp tick_layout_param_name(target_module, target_name, decl_map) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{args: [layout_name | _]} when is_binary(layout_name) -> {:ok, layout_name}
      _ -> :error
    end
  end

  defp layout_field_ref(layout_ref, field, {target_module, target_name}, decl_map, env) do
    layout_env =
      env
      |> Map.put(:__program_decls__, decl_map)
      |> Map.put_new(:__module__, target_module)

    case layout_arg_type({target_module, target_name}, decl_map) do
      layout_type when is_binary(layout_type) ->
        shape = CExpr.record_shape_for_type(layout_type, layout_env)
        Host.record_get_int_expr(layout_ref, field, shape, layout_env)

      _ ->
        nil
    end
  end

  defp layout_arg_type({target_module, target_name}, decl_map) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{type: type} when is_binary(type) ->
        type
        |> Host.function_arg_types()
        |> Enum.at(0)
        |> Host.normalize_type_name()

      %{args: [layout_name | _]} when is_binary(layout_name) ->
        layout_name
        |> layout_param_type_name()

      _ ->
        nil
    end
  end

  defp layout_param_type_name(param) do
    param
    |> to_string()
    |> then(fn name ->
      case name do
        <<first::utf8, rest::binary>> ->
          String.upcase(<<first::utf8>>) <> rest

        _ ->
          name
      end
    end)
  end

  defp polar_tick_line_emit(next) do
    """
            #{Commands.scene_emit_guard_open()}
            elmc_draw_cmd_init(&scene_cmd, #{Host.generated_draw_kind_macro(Elmc.Backend.Pebble.draw_kind_id!(:line))});
            scene_cmd.p0 = direct_tick_outer_x_#{next};
            scene_cmd.p1 = direct_tick_outer_y_#{next};
            scene_cmd.p2 = direct_tick_inner_x_#{next};
            scene_cmd.p3 = direct_tick_inner_y_#{next};
            scene_cmd.p4 = ELMC_COLOR_WHITE;
            #{Catch.push_cmd_check()}
            #{Commands.scene_emit_guard_close()}
    """
  end

  defp polar_tick_labeled_emit(
         scale,
         item_var,
         text_c_name,
         cx_ref,
         cy_ref,
         outer_ref,
         label_radius_extra,
         {box_dx, box_dy, box_w, box_h},
         next
       ) do
    """
            #{Commands.scene_emit_guard_open()}
            elmc_draw_cmd_init(&scene_cmd, #{Host.generated_draw_kind_macro(Elmc.Backend.Pebble.draw_kind_id!(:line))});
            scene_cmd.p0 = direct_tick_outer_x_#{next};
            scene_cmd.p1 = direct_tick_outer_y_#{next};
            scene_cmd.p2 = direct_tick_inner_x_#{next};
            scene_cmd.p3 = direct_tick_inner_y_#{next};
            scene_cmd.p4 = ELMC_COLOR_WHITE;
            #{Catch.push_cmd_check()}
            #{Commands.scene_emit_guard_close()}
            const elmc_int_t direct_tick_label_x_#{next} = elmc_polar_point_x(#{cx_ref}, #{cy_ref}, (#{outer_ref} + #{label_radius_extra}), direct_tick_angle_#{next});
            const elmc_int_t direct_tick_label_y_#{next} = elmc_polar_point_y(#{cx_ref}, #{cy_ref}, (#{outer_ref} + #{label_radius_extra}), direct_tick_angle_#{next});
            {
              ElmcValue *direct_tick_label_box_#{next} = NULL;
              elmc_int_t rec_values_#{next}[4] = { (direct_tick_label_x_#{next} - #{box_dx}), (direct_tick_label_y_#{next} - #{box_dy}), #{box_w}, #{box_h} };
              Rc = elmc_record_new_values_ints(&direct_tick_label_box_#{next}, 4, rec_values_#{next});
              CHECK_RC(Rc);
              elmc_scene_text_from_nonzero_int(scene_cmd.text, (#{item_var} * #{scale}));
              scene_cmd.text[63] = '\\0';
              Rc = #{text_c_name}_commands_append_native(ELMC_COLOR_WHITE, direct_tick_label_box_#{next}, scene_cmd.text, writer);
              CHECK_RC(Rc);
              elmc_release(direct_tick_label_box_#{next});
            }
    """
  end

  defp polar_scale_tick_text_target(_body_expr, :nothing, _module_name), do: {:ok, nil}

  defp polar_scale_tick_text_target(body_expr, {:from_int, _}, module_name) do
    case polar_scale_tick_text_call(body_expr, module_name) do
      nil -> :error
      target -> {:ok, target}
    end
  end

  defp polar_scale_tick_text_target(_, _, _), do: :error

  defp polar_scale_tick_text_call(expr, module_name) do
    expr
    |> Host.unwrap_let_chain(%{})
    |> elem(0)
    |> find_text_call_target(module_name)
  end

  defp find_text_call_target(expr, module_name)

  defp find_text_call_target(%{op: :case, branches: branches}, module_name)
       when is_list(branches) do
    Enum.find_value(branches, fn branch ->
      find_text_call_target(Map.get(branch, :expr) || branch, module_name)
    end)
  end

  defp find_text_call_target(%{op: :list_literal, items: items}, module_name)
       when is_list(items) do
    Enum.find_value(items, &find_text_call_target(&1, module_name))
  end

  defp find_text_call_target(%{op: :qualified_call, target: target, args: args}, _module_name)
       when is_binary(target) and is_list(args) do
    if ui_draw_target?(target) or length(args) != 3 do
      nil
    else
      Host.split_qualified_function_target(Host.normalize_special_target(target))
    end
  end

  defp find_text_call_target(%{op: :call, name: name, args: args}, module_name)
       when is_binary(name) and is_list(args) and length(args) >= 3 and is_binary(module_name) do
    {module_name, name}
  end

  defp find_text_call_target(expr, module_name) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.find_value(&find_text_call_target(&1, module_name))
  end

  defp find_text_call_target(_, _), do: nil

  defp ui_draw_target?(target) do
    case Host.normalize_special_target(target) do
      "Pebble.Ui." <> _ -> true
      _ -> String.starts_with?(target, "Pebble.Ui.")
    end
  end

  defp parse_tick_label_layout(body_expr) do
    body_expr
    |> Host.unwrap_let_chain(%{})
    |> elem(0)
    |> find_label_point_radius_extra()
    |> case do
      {:ok, radius_extra, box} -> %{label_radius_extra: radius_extra, label_box: box}
      _ -> %{}
    end
  end

  defp find_label_point_radius_extra(%{op: :case, branches: branches}) when is_list(branches) do
    Enum.find_value(branches, :error, fn
      %{pattern: %{name: "Just"}, expr: expr} -> find_label_point_radius_extra(expr)
      %{name: "Just", expr: expr} -> find_label_point_radius_extra(expr)
      _ -> :error
    end)
    |> case do
      {:ok, _, _} = ok -> ok
      _ -> :error
    end
  end

  defp find_label_point_radius_extra(%{op: :list_literal, items: items}) when is_list(items) do
    Enum.find_value(items, :error, &find_label_point_radius_extra/1)
    |> case do
      {:ok, _, _} = ok -> ok
      _ -> :error
    end
  end

  defp find_label_point_radius_extra(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}) do
    with {:ok, radius_extra, _} <- find_point_at_radius_extra(value_expr),
         {:ok, _, box} <- find_label_box_record(in_expr) do
      {:ok, radius_extra, box}
    else
      _ -> find_label_point_radius_extra(in_expr)
    end
  end

  defp find_label_point_radius_extra(_), do: :error

  defp find_point_at_radius_extra(%{op: :call, name: _name, args: args})
       when is_list(args) and length(args) == 4 do
    case radius_add_extra(Enum.at(args, 2)) do
      {:ok, extra} -> {:ok, extra, nil}
      _ -> :error
    end
  end

  defp find_point_at_radius_extra(%{op: :qualified_call, target: target, args: args}) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {_mod, _name} ->
        find_point_at_radius_extra(%{op: :call, name: "point", args: args})

      _ ->
        :error
    end
  end

  defp radius_add_extra(%{op: :call, name: name, args: [left, %{op: :int_literal, value: extra}]})
       when name in ["__add__", "__sub__"] do
    if radius_field_expr?(left), do: {:ok, extra}, else: :error
  end

  defp radius_add_extra(%{op: :call, name: name, args: [%{op: :int_literal, value: extra}, right]})
       when name in ["__add__", "__sub__"] do
    if radius_field_expr?(right), do: {:ok, extra}, else: :error
  end

  defp radius_add_extra(%{op: :int_literal, value: extra}), do: {:ok, extra}

  defp radius_add_extra(_), do: :error

  defp radius_field_expr?(%{op: :field_access, field: field}), do: field in ["outerRadius", "radius"]
  defp radius_field_expr?(_), do: false

  defp record_field_name(%{op: :field_access, field: field}), do: field
  defp record_field_name(_), do: nil

  defp find_label_box_record(%{op: :list_literal, items: items}) when is_list(items) do
    Enum.find_value(items, :error, fn
      %{op: :qualified_call, target: target, args: [_color, bounds, _label]} ->
        if ui_draw_target?(target) do
          :error
        else
          case bounds do
            %{op: :record_literal, fields: fields} -> parse_xywh_box(fields)
            _ -> :error
          end
        end

      %{op: :call, name: _name, args: [_color, bounds, _label]} ->
        case bounds do
          %{op: :record_literal, fields: fields} -> parse_xywh_box(fields)
          _ -> :error
        end

      _ ->
        :error
    end)
  end

  defp find_label_box_record(_), do: :error

  defp parse_xywh_box(fields) when is_list(fields) do
    field_map = Map.new(fields, fn %{name: name, expr: expr} -> {name, expr} end)

    with w when is_integer(w) <- literal_int(field_map["w"]),
         h when is_integer(h) <- literal_int(field_map["h"]),
         {dx, dy} <- label_box_offsets(field_map["x"], field_map["y"]) do
      {:ok, nil, {dx, dy, w, h}}
    else
      _ -> :error
    end
  end

  defp label_box_offsets(x_expr, y_expr) do
    with {x_field, x_off} <- sub_offset(x_expr),
         {y_field, y_off} <- sub_offset(y_expr),
         true <- x_field == "x" and y_field == "y" do
      {x_off, y_off}
    else
      _ -> :error
    end
  end

  defp sub_offset(%{op: :call, name: "__sub__", args: [left, %{op: :int_literal, value: off}]}),
    do: {record_field_name(left), off}

  defp sub_offset(%{op: :call, name: "__sub__", args: [%{op: :int_literal, value: off}, right]}),
    do: {record_field_name(right), off}

  defp sub_offset(_), do: :error

  defp polar_scale_tick_target?({target_module, target_name}, decl_map) do
    case Map.get(decl_map, {target_module, target_name}) do
      %{args: args, expr: expr} when is_list(args) and length(args) >= 2 ->
        polar_scale_tick_body?(expr)

      _ ->
        false
    end
  end

  defp polar_scale_tick_body?(expr) do
    expr
    |> Host.unwrap_let_chain(%{})
    |> elem(0)
    |> expr_contains_line_draw?()
  end

  defp ui_line_target?(target) do
    Host.normalize_special_target(target) == "Pebble.Ui.line"
  end

  defp expr_contains_line_draw?(%{op: :qualified_call, target: target, args: args}) do
    if ui_line_target?(target) do
      true
    else
      case args do
        [inner] ->
          case Host.normalize_special_target(target) do
            "Pebble.Ui.group" -> expr_contains_line_draw?(inner)
            _ -> false
          end

        _ ->
          false
      end
    end
  end

  defp expr_contains_line_draw?(%{op: :call, name: "line", args: _args}) do
    true
  end

  defp expr_contains_line_draw?(%{op: :case, branches: branches}) when is_list(branches) do
    Enum.any?(branches, fn branch ->
      expr_contains_line_draw?(Map.get(branch, :expr) || branch)
    end)
  end

  defp expr_contains_line_draw?(%{op: :list_literal, items: items}) when is_list(items) do
    Enum.any?(items, &expr_contains_line_draw?/1)
  end

  defp expr_contains_line_draw?(%{op: :let_in, in_expr: in_expr}), do: expr_contains_line_draw?(in_expr)

  defp expr_contains_line_draw?(expr) when is_map(expr) do
    expr |> Map.values() |> Enum.any?(&expr_contains_line_draw?/1)
  end

  defp expr_contains_line_draw?(_), do: false

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
