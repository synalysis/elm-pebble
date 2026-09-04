defmodule ElmEx.Typesys.Infer do
  @moduledoc """
  Algorithm W over frontend AST. Annotates expressions with `:elm_type`.
  """

  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.Lowerer
  alias ElmEx.Typesys.{Diagnostic, Env, Pattern, Solve, Type}

  @spec run([FrontendModule.t()], Env.t()) :: {[FrontendModule.t()], [map()], Env.t()}
  def run(modules, env) when is_list(modules) do
    {modules, env} =
      Enum.map_reduce(modules, env, fn mod, env ->
        infer_module(mod, env)
      end)

    {modules, env.errors, env}
  end

  defp infer_module(%FrontendModule{} = mod, env) do
    exports = Lowerer.project_module_exports(Map.values(env.modules))
    {alias_map, _members, unqualified, _wild, _types} = Lowerer.import_resolution_for(mod, exports)

    local_names =
      mod.declarations
      |> Enum.filter(&(&1.kind in [:function_definition, :function_signature]))
      |> Enum.map(& &1.name)
      |> MapSet.new()

    env =
      env
      |> Env.put_import_lookup(%{
        alias_map: alias_map,
        import_unqualified_map: unqualified,
        local_call_names: local_names,
        current_module: mod.name
      })
      |> Env.merge_exposed_imports(mod)

    env = predeclare_functions(mod, env)
    env = check_mutual_value_cycles(mod, env)

    {decls, env} =
      Enum.map_reduce(mod.declarations, env, fn decl, env ->
        infer_decl(decl, mod, env)
      end)

    {%{mod | declarations: decls}, env}
  end

  defp predeclare_functions(%FrontendModule{} = mod, env) do
    Enum.reduce(mod.declarations, env, fn
      %{kind: :function_definition, name: name, args: args}, env ->
        qualified = "#{mod.name}.#{name}"

        {ret, env} = Env.fresh(env)

        {arg_ts, env} =
          Enum.map_reduce(args || [], env, fn _arg, env -> Env.fresh(env) end)

        scheme =
          case Env.lookup_value(env, qualified) do
            {:forall, _, {:fun, _, _}} = existing -> existing
            {:forall, _, {:named, _, _}} = existing -> existing
            {:forall, _, {:record, _, _}} = existing -> existing
            {:forall, _, {:tuple, _}} = existing -> existing
            _ -> Env.mono(Type.funs(arg_ts, ret))
          end

        env
        |> Env.put_value(qualified, scheme)
        |> Env.put_value(name, scheme)

      _, env ->
        env
    end)
  end

  defp infer_decl(%{kind: :function_definition, name: name} = decl, mod, env) do
    args = Map.get(decl, :args) || []
    expr = Map.get(decl, :expr)
    loc = loc(mod, name, decl)
    rigid_keep = env.rigid_ids
    values_before = env.values

    {env, arg_types} =
      Enum.reduce(args, {env, []}, fn arg, {env, acc} ->
        {env, t} = bind_fun_arg(env, arg, loc)
        {env, acc ++ [t]}
      end)

    annotated? = annotated_function?(env, mod.name, name)

    {expected, env} =
      case Env.lookup_value(env, "#{mod.name}.#{name}") || Env.lookup_value(env, name) do
        nil ->
          {nil, env}

        scheme when annotated? ->
          Env.instantiate_rigid(env, scheme)

        scheme ->
          Env.instantiate(env, scheme)
      end

    env = check_value_cycle(env, name, args, expr, loc)

    env =
      if expected do
        {exp_params, _exp_ret} = Type.params_and_return(Type.subst_apply(env.subst, expected))

        if length(exp_params) == length(arg_types) do
          Enum.zip(arg_types, exp_params)
          |> Enum.reduce(env, fn {got, want}, env ->
            case Solve.unify(env, want, got, loc) do
              {:ok, env} -> env
              {:error, env, _} -> env
            end
          end)
        else
          env
        end
      else
        env
      end

    {body_type, expr, env} = infer_expr(env, expr, loc)

    env =
      if expected do
        inferred = Type.funs(arg_types, Type.subst_apply(env.subst, body_type))

        case Solve.unify(env, Type.subst_apply(env.subst, expected), inferred, loc) do
          {:ok, env} -> env
          {:error, env, _} -> env
        end
      else
        env
      end

    inferred = Type.funs(arg_types, Type.subst_apply(env.subst, body_type))

    scheme =
      if annotated? do
        Env.lookup_value(env, "#{mod.name}.#{name}") || Env.generalize(env, inferred)
      else
        Env.generalize(env, inferred)
      end

    env = Env.drop_rigid(env, rigid_keep)
    env = %{env | values: values_before}
    env = Env.put_value(env, "#{mod.name}.#{name}", scheme)
    env = Env.put_value(env, name, scheme)
    {Map.put(decl, :expr, apply_types(env, expr)), env}
  end

  defp infer_decl(decl, _mod, env), do: {decl, env}

  defp annotated_function?(env, mod, name) do
    case Env.lookup_value(env, "#{mod}.#{name}") do
      {:forall, vars, _} when vars != [] -> true
      {:forall, [], type} -> not placeholder_fun?(type)
      _ -> false
    end
  end

  defp placeholder_fun?(type) do
    {params, ret} = Type.params_and_return(type)
    match?({:var, _}, ret) and Enum.all?(params, &match?({:var, _}, &1))
  end

  defp infer_expr(env, "()", _loc), do: {:unit, "()", env}

  defp infer_expr(env, name, loc) when is_binary(name) do
    {t, env} = lookup_or_fresh(env, name, loc)
    {t, name, env}
  end

  defp infer_expr(env, expr, _loc) when not is_map(expr) do
    {t, env} = Env.fresh(env)
    {t, expr, env}
  end

  defp infer_expr(env, %{op: op} = expr, loc) do
    {type, expr, env} = infer_op(env, op, expr, loc)
    type = Type.subst_apply(env.subst, type)
    {type, Map.put(expr, :elm_type, type), env}
  end

  defp infer_op(env, :int_literal, expr, _loc), do: number_fresh(env, expr)
  defp infer_op(env, :float_literal, expr, _loc), do: {Type.float(), expr, env}
  defp infer_op(env, :string_literal, expr, _loc), do: {Type.string(), expr, env}
  defp infer_op(env, :char_literal, expr, _loc), do: {Type.char(), expr, env}
  defp infer_op(env, :bool_literal, expr, _loc), do: {Type.bool(), expr, env}
  defp infer_op(env, :cmd_none, expr, _loc) do
    {msg, env} = Env.fresh(env)
    {Type.cmd(msg), expr, env}
  end

  defp infer_op(env, :var, %{name: name} = expr, loc) do
    instantiate_name(env, name, expr, loc)
  end

  defp infer_op(env, :call, %{name: name, args: args} = expr, loc) do
    infer_call(env, name, args, expr, loc)
  end

  defp infer_op(env, :qualified_call, %{target: target, args: args} = expr, loc) do
    infer_call(env, target, args || [], expr, loc)
  end

  defp infer_op(env, :qualified_call1, %{target: target} = expr, loc) do
    infer_call(env, target, [], expr, loc)
  end

  defp infer_op(env, :constructor_call, %{target: target, args: args} = expr, loc) do
    infer_call(env, target, args || [], expr, loc)
  end

  defp infer_op(env, op, %{target: target} = expr, loc)
       when op in [:constructor_ref, :qualified_ref] do
    instantiate_name(env, target, expr, loc)
  end

  defp infer_op(env, :lambda, %{args: args, body: body} = expr, loc) do
    values_before = env.values

    {env, arg_types} =
      Enum.reduce(args || [], {env, []}, fn arg, {env, acc} ->
        {env, t} = bind_fun_arg(env, arg, loc)
        {env, acc ++ [t]}
      end)

    {ret, body, env} = infer_expr(env, body, loc)
    env = %{env | values: values_before}
    {Type.funs(arg_types, ret), %{expr | body: body}, env}
  end

  defp infer_op(env, :let_in, %{name: name, value_expr: value, in_expr: rest} = expr, loc) do
    values_before = env.values
    {pre, env} = Env.fresh(env)
    env = Env.put_value(env, name, Env.mono(pre))
    env = check_value_cycle(env, name, lambda_args(value), value, loc)
    {val_t, value, env} = infer_expr(env, value, loc)
    env = unify_ok(env, pre, val_t, loc)
    env = generalize_let_names(env, [name])
    {in_t, rest, env} = infer_expr(env, rest, loc)
    env = %{env | values: values_before}
    {in_t, %{expr | value_expr: value, in_expr: rest}, env}
  end

  defp infer_op(env, :let_bindings, %{bindings: bindings, in_expr: rest} = expr, loc) do
    values_before = env.values
    env = predeclare_let_names(env, bindings)

    {bindings, env} =
      Enum.map_reduce(bindings || [], env, fn bind, env ->
        infer_binding(env, bind, loc)
      end)

    env = generalize_let_names(env, let_binding_names(bindings))
    {in_t, rest, env} = infer_expr(env, rest, loc)
    env = %{env | values: values_before}
    {in_t, %{expr | bindings: bindings, in_expr: rest}, env}
  end

  defp infer_op(env, :if, expr, loc) do
    cond_key = if Map.has_key?(expr, :then_expr), do: :then_expr, else: :then
    else_key = if Map.has_key?(expr, :else_expr), do: :else_expr, else: :else
    {cond_t, cond_e, env} = infer_expr(env, Map.get(expr, :cond), loc)
    env = unify_ok(env, Type.bool(), cond_t, loc)
    {then_t, then_e, env} = infer_expr(env, Map.get(expr, cond_key), loc)
    {else_t, else_e, env} = infer_expr(env, Map.get(expr, else_key), loc)
    env = unify_ok(env, then_t, else_t, loc)

    expr =
      expr
      |> Map.put(:cond, cond_e)
      |> Map.put(cond_key, then_e)
      |> Map.put(else_key, else_e)

    {then_t, expr, env}
  end

  defp infer_op(env, :case, expr, loc) do
    subject = expr.subject
    {subj_t, subject, env} = infer_subject(env, subject, loc)
    values_before = env.values
    just_payload = maybe_just_catchall_payload(env, subj_t, expr.branches)

    {branches, branch_types, env} =
      Enum.reduce(expr.branches || [], {[], [], env}, fn branch, {brs, tys, env} ->
        env = %{env | values: values_before}
        {pat_t, binds, pattern, env} = infer_pattern(env, Map.get(branch, :pattern), loc)

        env =
          if just_payload && catchall_pattern?(pattern) do
            unify_ok(env, just_payload, pat_t, loc)
          else
            unify_ok(env, subj_t, pat_t, loc)
          end

        env =
          Enum.reduce(binds, env, fn {name, type}, env ->
            Env.put_value(env, name, Env.mono(type))
          end)

        {body_t, body, env} = infer_expr(env, Map.get(branch, :expr), loc)
        branch = %{branch | pattern: pattern, expr: body}
        {brs ++ [branch], tys ++ [body_t], env}
      end)

    env = %{env | values: values_before}

    {result, env} =
      case branch_types do
        [] ->
          Env.fresh(env)

        [first | rest] ->
          env =
            Enum.reduce(rest, env, fn t, env ->
              unify_ok(env, first, t, loc)
            end)

          {first, env}
      end

    {result, %{expr | subject: subject, branches: branches}, env}
  end

  defp infer_op(env, :tuple2, %{left: l, right: r} = expr, loc) do
    {lt, l, env} = infer_expr(env, l, loc)
    {rt, r, env} = infer_expr(env, r, loc)
    {Type.tuple([lt, rt]), %{expr | left: l, right: r}, env}
  end

  defp infer_op(env, :tuple3, %{a: a, b: b, c: c} = expr, loc) do
    {at, a, env} = infer_expr(env, a, loc)
    {bt, b, env} = infer_expr(env, b, loc)
    {ct, c, env} = infer_expr(env, c, loc)
    {Type.tuple([at, bt, ct]), %{expr | a: a, b: b, c: c}, env}
  end

  defp infer_op(env, :list_literal, %{items: items} = expr, loc) do
    {elem, env} = Env.fresh(env)

    {items, env} =
      Enum.map_reduce(items || [], env, fn item, env ->
        {t, item, env} = infer_expr(env, item, loc)
        env = unify_ok(env, elem, t, loc)
        {item, env}
      end)

    {Type.list(elem), %{expr | items: items}, env}
  end

  defp infer_op(env, :record_literal, %{fields: fields} = expr, loc) do
    {field_map, fields, env} =
      Enum.reduce(fields || [], {%{}, [], env}, fn field, {map, acc, env} ->
        name = field_name(field)
        value = field_value(field)
        {t, value, env} = infer_expr(env, value, loc)
        field = put_field_value(field, value)
        {Map.put(map, name, t), acc ++ [field], env}
      end)

    {Type.record(field_map), %{expr | fields: fields}, env}
  end

  defp infer_op(env, :record_update, %{base: base, fields: fields} = expr, loc) do
    {base_t, base, env} = infer_expr(env, base, loc)
    {row, env} = Env.fresh(env)

    {field_map, fields, env} =
      Enum.reduce(fields || [], {%{}, [], env}, fn field, {map, acc, env} ->
        name = field_name(field)
        value = field_value(field)
        {t, value, env} = infer_expr(env, value, loc)
        {Map.put(map, name, t), acc ++ [put_field_value(field, value)], env}
      end)

    expected = Type.record(field_map, row)
    env = unify_ok(env, expected, base_t, loc)
    {base_t, %{expr | base: base, fields: fields}, env}
  end

  defp infer_op(env, :field_access, %{arg: arg, field: field} = expr, loc) do
    {arg_t, arg, env} = infer_value(env, arg, loc)
    {field_t, env} = Env.fresh(env)
    {row, env} = Env.fresh(env)
    expected = Type.record(%{field => field_t}, row)
    env = unify_ok(env, expected, arg_t, loc)
    {field_t, %{expr | arg: arg}, env}
  end

  defp infer_op(env, :field_call, %{arg: arg, field: field, args: args} = expr, loc) do
    {fun_t, access, env} =
      infer_op(env, :field_access, %{op: :field_access, arg: arg, field: field}, loc)

    {ret, args, env} = apply_args(env, fun_t, args || [], loc)
    {ret, %{expr | arg: access.arg, args: args}, env}
  end

  defp infer_op(env, :compare, %{left: l, right: r} = expr, loc) do
    {lt, l, env} = infer_expr(env, l, loc)
    {rt, r, env} = infer_expr(env, r, loc)

    env =
      case Map.get(expr, :kind) do
        kind when kind in [:lt, :gt, :lte, :gte] ->
          {cmp, env} = Env.fresh_constrained(env, :comparable)
          env = unify_ok(env, cmp, lt, loc)
          unify_ok(env, cmp, rt, loc)

        _ ->
          # `(==)` / `(/=)` are fully polymorphic; only `<`/`>`/`<=`/`>=` need comparable.
          unify_ok(env, lt, rt, loc)
      end

    {Type.bool(), %{expr | left: l, right: r}, env}
  end

  defp infer_op(env, op, %{var: var, value: _} = expr, loc) when op in [:add_const, :sub_const] do
    {num, env} = Env.fresh_constrained(env, :number)
    {vt, _e, env} = instantiate_name(env, var, %{op: :var, name: var}, loc)
    env = unify_ok(env, num, vt, loc)
    {num, expr, env}
  end

  defp infer_op(env, op, %{left: l, right: r} = expr, loc) when op in [:add_vars, :sub_vars] do
    {num, env} = Env.fresh_constrained(env, :number)
    {lt, _, env} = instantiate_name(env, l, %{op: :var, name: l}, loc)
    {rt, _, env} = instantiate_name(env, r, %{op: :var, name: r}, loc)
    env = unify_ok(env, num, lt, loc)
    env = unify_ok(env, num, rt, loc)
    {num, expr, env}
  end

  defp infer_op(env, op, %{left: l, right: r} = expr, loc) when op in [:bool_and, :bool_or] do
    {lt, l, env} = infer_expr(env, l, loc)
    {rt, r, env} = infer_expr(env, r, loc)
    env = unify_ok(env, Type.bool(), lt, loc)
    env = unify_ok(env, Type.bool(), rt, loc)
    {Type.bool(), %{expr | left: l, right: r}, env}
  end

  defp infer_op(env, :apply_left, %{fn_expr: fn_e, arg: arg} = expr, loc) do
    {ft, fn_e, env} = infer_expr(env, fn_e, loc)
    {ret, [arg], env} = apply_args(env, ft, [arg], loc)
    {ret, %{expr | fn_expr: fn_e, arg: arg}, env}
  end

  defp infer_op(env, :pipe_chain, %{base: base, steps: steps} = expr, loc) do
    {t, base, env} = infer_expr(env, base, loc)

    {t, steps, env} =
      Enum.reduce(steps || [], {t, [], env}, fn step, {t, acc, env} ->
        {st, step, env} = infer_expr(env, step, loc)
        {ret, env} = apply_pipe(env, st, t, loc)
        {ret, acc ++ [step], env}
      end)

    {t, %{expr | base: base, steps: steps}, env}
  end

  defp infer_op(env, :compose_left, expr, loc), do: infer_compose(env, expr, :left, loc)
  defp infer_op(env, :compose_right, expr, loc), do: infer_compose(env, expr, :right, loc)

  defp infer_op(env, :tuple_first_expr, %{arg: arg} = expr, loc) do
    {t, arg, env} = infer_expr(env, arg, loc)
    {a, env} = Env.fresh(env)
    {b, env} = Env.fresh(env)
    env = unify_ok(env, Type.tuple([a, b]), t, loc)
    {a, %{expr | arg: arg}, env}
  end

  defp infer_op(env, :tuple_second_expr, %{arg: arg} = expr, loc) do
    {t, arg, env} = infer_expr(env, arg, loc)
    {a, env} = Env.fresh(env)
    {b, env} = Env.fresh(env)
    env = unify_ok(env, Type.tuple([a, b]), t, loc)
    {b, %{expr | arg: arg}, env}
  end

  defp infer_op(env, :string_length_expr, %{arg: arg} = expr, loc) do
    {t, arg, env} = infer_expr(env, arg, loc)
    env = unify_ok(env, Type.string(), t, loc)
    {Type.int(), %{expr | arg: arg}, env}
  end

  defp infer_op(env, :char_from_code_expr, %{arg: arg} = expr, loc) do
    {t, arg, env} = infer_expr(env, arg, loc)
    env = unify_ok(env, Type.int(), t, loc)
    {Type.char(), %{expr | arg: arg}, env}
  end

  defp infer_op(env, :bad_tuple, expr, loc) do
    arity = Map.get(expr, :arity) || length(Map.get(expr, :items) || [])

    env =
      Env.add_error(
        env,
        Diagnostic.error(
          "bad_tuple",
          "Tuples can only have two or three items, not #{arity}.",
          loc
        )
      )

    {t, env} = Env.fresh(env)
    {t, expr, env}
  end

  defp infer_op(env, :unsupported, expr, loc) do
    src = Map.get(expr, :source) || "this expression"

    env =
      if four_plus_tuple_source?(src) do
        Env.add_error(
          env,
          Diagnostic.error(
            "bad_tuple",
            "Tuples can only have two or three items.",
            loc
          )
        )
      else
        Env.add_error(
          env,
          Diagnostic.error(
            "unsupported_expr",
            "I cannot typecheck this expression yet: #{src}",
            loc
          )
        )
      end

    {t, env} = Env.fresh(env)
    {t, expr, env}
  end

  defp infer_op(env, _op, expr, loc) do
    infer_children(env, expr, loc)
  end

  defp infer_children(env, expr, loc) do
    {t, env} = Env.fresh(env)

    expr =
      expr
      |> Enum.reduce(expr, fn
        {key, val}, acc when is_map(val) and is_map_key(val, :op) ->
          {_t, val, _env} = infer_expr(env, val, loc)
          Map.put(acc, key, val)

        {key, vals}, acc when is_list(vals) ->
          Map.put(
            acc,
            key,
            Enum.map(vals, fn
              %{op: _} = child ->
                {_t, child, _} = infer_expr(env, child, loc)
                child

              other ->
                other
            end)
          )

        _, acc ->
          acc
      end)

    {t, expr, env}
  end

  defp infer_call(env, name, args, expr, loc) do
    args = args || []
    resolved = resolve_name(env, name)
    schemes = lookup_schemes(env, name, resolved)

    case schemes do
      [] ->
        {fun_t, env} = lookup_or_fresh(env, name, loc)
        {ret, args, env} = apply_args(env, fun_t, args, loc)
        {ret, Map.put(expr, :args, args), env}

      [scheme] ->
        {fun_t, env} = Env.instantiate(env, scheme)
        {ret, args, env} = apply_args(env, fun_t, args, loc)
        {ret, Map.put(expr, :args, args), env}

      many ->
        apply_alt_schemes(env, many, args, expr, loc)
    end
  end

  defp lookup_schemes(env, name, resolved) do
    {first, second} =
      if is_binary(name) and String.contains?(name, ".") do
        {resolved, name}
      else
        {name, resolved}
      end

    [first, second, demangle_pkg_name(first), demangle_pkg_name(second)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(&Env.lookup_value_schemes(env, &1))
    |> Enum.uniq()
  end

  defp demangle_pkg_name(name) when is_binary(name) do
    case String.split(name, ".", parts: 3) do
      ["Pkg", _pkg, rest] when rest != "" -> rest
      _ -> nil
    end
  end

  defp demangle_pkg_name(_), do: nil

  defp apply_alt_schemes(env, schemes, args, expr, loc) do
    before = length(env.errors)
    arity = length(args)

    # Prefer the overload whose declared arity matches the call. Otherwise a
    # longer kernel/package scheme can "succeed" as a partial application when
    # an argument is still an unbound field (for example `Ui.text model.shown`).
    schemes =
      Enum.sort_by(schemes, fn scheme ->
        if scheme_param_count(scheme) == arity, do: 0, else: 1
      end)

    found =
      Enum.find_value(schemes, fn scheme ->
        {fun_t, env1} = Env.instantiate(env, scheme)
        {ret, typed_args, env1} = apply_args(env1, fun_t, args, loc)

        if length(env1.errors) == before do
          {ret, Map.put(expr, :args, typed_args), env1}
        end
      end)

    if found do
      found
    else
      {fun_t, env} = Env.instantiate(env, hd(schemes))
      {ret, typed_args, env} = apply_args(env, fun_t, args, loc)
      {ret, Map.put(expr, :args, typed_args), env}
    end
  end

  defp scheme_param_count({:forall, _vars, type}), do: scheme_param_count(type)

  defp scheme_param_count(type) do
    {params, _ret} = Type.params_and_return(type)
    length(params)
  end

  defp apply_args(env, fun_t, [], _loc), do: {fun_t, [], env}

  defp apply_args(env, fun_t, args, loc) do
    {typed, env} =
      Enum.map_reduce(args, env, fn arg, env ->
        {t, arg, env} = infer_expr(env, arg, loc)
        {{t, arg}, env}
      end)

    {ret, env} =
      Enum.reduce(typed, {fun_t, env}, fn {arg_t, _arg}, {fun_t, env} ->
        apply_one(env, Type.subst_apply(env.subst, fun_t), arg_t, loc)
      end)

    {ret, Enum.map(typed, &elem(&1, 1)), env}
  end

  defp apply_one(env, {:fun, from, to}, arg_t, loc) do
    {to, unify_ok(env, from, arg_t, loc)}
  end

  defp apply_one(env, {:named, _, _} = fun_t, arg_t, loc) do
    case Env.expand_type(env, fun_t) do
      {:fun, _, _} = expanded ->
        apply_one(env, expanded, arg_t, loc)

      _ ->
        apply_not_function(env, fun_t, loc)
    end
  end

  defp apply_one(env, {:var, _} = fun_t, arg_t, loc) do
    {ret, env} = Env.fresh(env)
    {ret, unify_ok(env, Type.fun(arg_t, ret), fun_t, loc)}
  end

  defp apply_one(env, fun_t, _arg_t, loc), do: apply_not_function(env, fun_t, loc)

  defp apply_not_function(env, fun_t, loc) do
    env =
      Env.add_error(
        env,
        Diagnostic.error(
          "function_call_arity",
          "This value is not a function, so it cannot take any more arguments.",
          loc
        )
      )

    {fun_t, env}
  end

  defp apply_pipe(env, step_t, value_t, loc) do
    {ret, env} = Env.fresh(env)
    env = unify_ok(env, Type.fun(value_t, ret), step_t, loc)
    {ret, env}
  end

  defp infer_compose(env, expr, dir, loc) do
    {ft, f, env} = infer_value(env, expr.f, loc)
    {gt, g, env} = infer_value(env, expr.g, loc)
    {a, env} = Env.fresh(env)
    {b, env} = Env.fresh(env)
    {c, env} = Env.fresh(env)

    env =
      case dir do
        :left ->
          env
          |> unify_ok(Type.fun(b, c), ft, loc)
          |> unify_ok(Type.fun(a, b), gt, loc)

        :right ->
          env
          |> unify_ok(Type.fun(a, b), ft, loc)
          |> unify_ok(Type.fun(b, c), gt, loc)
      end

    {Type.fun(a, c), %{expr | f: f, g: g}, env}
  end

  defp infer_binding(env, %{kind: :name, name: name, value: value} = bind, loc) do
    env = check_value_cycle(env, name, lambda_args(value), value, loc)
    {t, value, env} = infer_expr(env, value, loc)

    env =
      case Env.lookup_value(env, name) do
        nil ->
          Env.put_value(env, name, Env.mono(Type.subst_apply(env.subst, t)))

        scheme ->
          {pre, env} = Env.instantiate(env, scheme)
          env = unify_ok(env, pre, t, loc)
          Env.put_value(env, name, Env.mono(Type.subst_apply(env.subst, t)))
      end

    {%{bind | value: value}, env}
  end

  defp infer_binding(env, %{kind: :discard, value: value} = bind, loc) do
    {_t, value, env} = infer_expr(env, value, loc)
    {%{bind | value: value}, env}
  end

  defp infer_binding(env, %{kind: kind, names: names, value: value} = bind, loc)
       when kind in [:tuple2, :tuple3] do
    {t, value, env} = infer_expr(env, value, loc)
    {elem_types, env} = Enum.map_reduce(names, env, fn _n, env -> Env.fresh(env) end)
    env = unify_ok(env, Type.tuple(elem_types), t, loc)

    env =
      Enum.zip(names, elem_types)
      |> Enum.reduce(env, fn {n, ty}, env -> Env.put_value(env, n, Env.mono(ty)) end)

    {%{bind | value: value}, env}
  end

  defp infer_binding(env, %{kind: :pattern, pattern: pattern, value: value} = bind, loc) do
    {t, value, env} = infer_expr(env, value, loc)
    {pat_t, binds, pattern, env} = infer_pattern(env, pattern, loc)
    env = unify_ok(env, t, pat_t, loc)

    env =
      Enum.reduce(binds, env, fn {name, type}, env ->
        Env.put_value(env, name, Env.mono(type))
      end)

    {%{bind | pattern: pattern, value: value}, env}
  end

  defp infer_binding(env, bind, _loc), do: {bind, env}

  defp predeclare_let_names(env, bindings) do
    Enum.reduce(List.wrap(bindings), env, fn
      %{kind: :name, name: name}, env when is_binary(name) ->
        {t, env} = Env.fresh(env)
        Env.put_value(env, name, Env.mono(t))

      _, env ->
        env
    end)
  end

  defp let_binding_names(bindings) do
    for %{kind: :name, name: name} <- List.wrap(bindings), is_binary(name), do: name
  end

  defp generalize_let_names(env, names) do
    names = Enum.filter(names, &is_binary/1)
    values_without = Enum.reduce(names, env.values, &Map.delete(&2, &1))

    Enum.reduce(names, env, fn name, env ->
      case Map.get(env.values, name) do
        {:forall, _, type} ->
          Env.put_value(env, name, Env.generalize(%{env | values: values_without}, type))

        _ ->
          env
      end
    end)
  end

  defp lambda_args(%{op: :lambda, args: args}) when is_list(args), do: args
  defp lambda_args(_), do: []

  # Toolchain case lowering treats `Nothing` + a bare variable as the Just
  # payload (same as elmx / plan tag-switch). Official Elm types the variable
  # as the whole Maybe; Pebble apps rely on the payload bind.
  defp maybe_just_catchall_payload(env, subj_t, branches) do
    nothing? = Enum.any?(branches, &nothing_pattern?/1)
    just? = Enum.any?(branches, &just_pattern?/1)
    catchall? = Enum.any?(branches, &catchall_branch?/1)

    if nothing? and catchall? and not just? do
      Type.maybe_payload(Type.subst_apply(env.subst, subj_t))
    else
      nil
    end
  end

  defp nothing_pattern?(branch), do: ctor_short(branch_pattern(branch)) == "Nothing"
  defp just_pattern?(branch), do: ctor_short(branch_pattern(branch)) == "Just"
  defp catchall_branch?(branch), do: catchall_pattern?(branch_pattern(branch))

  defp branch_pattern(%{pattern: pat}), do: pat
  defp branch_pattern(pat), do: pat

  defp catchall_pattern?(%{kind: kind}) when kind in [:var, :wildcard], do: true
  defp catchall_pattern?(_), do: false

  defp ctor_short(%{kind: :constructor, name: name}) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp ctor_short(_), do: nil

  defp infer_pattern(env, %{kind: :wildcard} = pat, _loc) do
    {t, env} = Env.fresh(env)
    {t, [], pat, env}
  end

  defp infer_pattern(env, %{kind: :var, name: name} = pat, _loc) do
    {t, env} = Env.fresh(env)
    {t, [{name, t}], pat, env}
  end

  defp infer_pattern(env, %{kind: :int} = pat, _loc), do: {Type.int(), [], pat, env}
  defp infer_pattern(env, %{kind: :char} = pat, _loc), do: {Type.char(), [], pat, env}
  defp infer_pattern(env, %{kind: :string} = pat, _loc), do: {Type.string(), [], pat, env}

  defp infer_pattern(env, %{kind: :bad_tuple, arity: arity} = pat, loc) do
    env =
      Env.add_error(
        env,
        Diagnostic.error(
          "bad_tuple",
          "Tuples can only have two or three items, not #{arity}.",
          loc
        )
      )

    {t, env} = Env.fresh(env)
    {t, [], pat, env}
  end

  defp infer_pattern(env, %{kind: :tuple, elements: elems} = pat, loc) do
    elems = flatten_tuple_pattern_elements(elems)

    if is_list(elems) and length(elems) > 3 do
      infer_pattern(env, %{kind: :bad_tuple, arity: length(elems)}, loc)
    else
    {pairs, env} =
      Enum.map_reduce(elems || [], env, fn el, env ->
        {t, binds, el, env} = infer_pattern(env, el, loc)
        {{t, binds, el}, env}
      end)

    types = Enum.map(pairs, &elem(&1, 0))
    binds = Enum.flat_map(pairs, &elem(&1, 1))
    elems = Enum.map(pairs, &elem(&1, 2))
    {Type.tuple(types), binds, %{pat | elements: elems}, env}
    end
  end

  defp infer_pattern(env, %{kind: :constructor, name: name} = pat, loc) do
    {fun_t, env} = lookup_or_fresh(env, name, loc)
    arg = Map.get(pat, :arg_pattern)
    bind = Map.get(pat, :bind)
    fun_t = Type.subst_apply(env.subst, fun_t)
    {params, ret} = Type.params_and_return(fun_t)

    arg_pats = ctor_arg_patterns(arg, length(params))

    {pat_t, binds, arg, env} =
      cond do
        arg_pats != [] and length(arg_pats) == length(params) ->
          {pairs, env} =
            Enum.zip(arg_pats, params)
            |> Enum.map_reduce(env, fn {el, want}, env ->
              {got, binds, el, env} = infer_pattern(env, el, loc)
              env = unify_ok(env, want, got, loc)
              {{binds, el}, env}
            end)

          binds = Enum.flat_map(pairs, &elem(&1, 0))
          binds = if is_binary(bind), do: [{bind, ret} | binds], else: binds
          {ret, binds, arg, env}

        is_map(arg) ->
          {arg_t, binds, arg, env} = infer_pattern(env, arg, loc)
          {fresh_ret, env} = Env.fresh(env)
          env = unify_ok(env, Type.fun(arg_t, fresh_ret), fun_t, loc)
          binds = if is_binary(bind), do: [{bind, fresh_ret} | binds], else: binds
          {fresh_ret, binds, arg, env}

        true ->
          payload_binds =
            if is_binary(bind) and params != [] do
              [{bind, hd(params)}]
            else
              []
            end

          {ret, payload_binds, arg, env}
      end

    {pat_t, binds, Map.put(pat, :arg_pattern, arg), env}
  end

  defp infer_pattern(env, %{kind: :record, fields: fields} = pat, _loc) do
    {field_map, binds, env} =
      Enum.reduce(fields || [], {%{}, [], env}, fn name, {map, binds, env} ->
        {t, env} = Env.fresh(env)
        {Map.put(map, name, t), [{name, t} | binds], env}
      end)

    {row, env} = Env.fresh(env)
    bind = Map.get(pat, :bind)
    type = Type.record(field_map, row)
    binds = if is_binary(bind), do: [{bind, type} | binds], else: binds
    {type, binds, pat, env}
  end

  defp infer_pattern(env, %{kind: :list, elements: elems} = pat, loc) do
    {elem, env} = Env.fresh(env)

    {pairs, env} =
      Enum.map_reduce(elems || [], env, fn el, env ->
        {t, binds, el, env} = infer_pattern(env, el, loc)
        env = unify_ok(env, elem, t, loc)
        {{binds, el}, env}
      end)

    binds = Enum.flat_map(pairs, &elem(&1, 0))
    elems = Enum.map(pairs, &elem(&1, 1))
    {Type.list(elem), binds, %{pat | elements: elems}, env}
  end

  defp infer_pattern(env, %{kind: :cons, head: head, tail: tail} = pat, loc) do
    {ht, hb, head, env} = infer_pattern(env, head, loc)
    {tt, tb, tail, env} = infer_pattern(env, tail, loc)
    env = unify_ok(env, Type.list(ht), tt, loc)
    {tt, hb ++ tb, %{pat | head: head, tail: tail}, env}
  end

  defp infer_pattern(env, %{kind: :unknown, source: source}, loc) do
    case Pattern.recover(source) do
      {:ok, recovered} ->
        infer_pattern(env, recovered, loc)

      :error ->
        env =
          Env.add_error(
            env,
            Diagnostic.error(
              "unsupported_pattern",
              "I cannot typecheck this pattern yet: #{source}",
              loc
            )
          )

        infer_pattern(env, %{kind: :wildcard}, loc)
    end
  end

  defp infer_pattern(env, %{kind: :alias, pattern: inner} = pat, loc) do
    {t, binds, inner, env} = infer_pattern(env, inner, loc)
    bind = Map.get(pat, :bind) || Map.get(pat, :name)
    binds = if is_binary(bind), do: [{bind, t} | binds], else: binds
    {t, binds, %{pat | pattern: inner}, env}
  end

  defp infer_pattern(env, pat, _loc) do
    {t, env} = Env.fresh(env)
    {t, [], pat, env}
  end

  defp ctor_arg_patterns(nil, _arity), do: []
  defp ctor_arg_patterns(_arg, arity) when arity <= 0, do: []
  defp ctor_arg_patterns(arg, 1), do: [arg]

  # `::` is `a -> List a -> List a`. The head may itself be a tuple, so a
  # 2-element payload is always [head, tail] — never flatten the head.
  defp ctor_arg_patterns(%{kind: :tuple, elements: [head, tail]}, 2), do: [head, tail]

  defp ctor_arg_patterns(%{kind: :tuple, elements: elems}, arity) when is_list(elems) and arity > 2 do
    cond do
      length(elems) == arity ->
        elems

      true ->
        flat = flatten_right_nested_ctor_args(elems)
        if length(flat) == arity, do: flat, else: []
    end
  end

  defp ctor_arg_patterns(_, _), do: []

  # `(a, b, c)` / `Map3 a b c d` payloads are right-nested pairs in the parser.
  # Only unwrap that spine; do not flatten a tuple that is a single argument.
  defp flatten_right_nested_ctor_args([left, %{kind: :tuple, elements: right}]) do
    [left | flatten_right_nested_ctor_args(right)]
  end

  defp flatten_right_nested_ctor_args(elems) when is_list(elems), do: elems

  # `(a, b, c)` is encoded as a right-nested pair in the expression parser.
  defp flatten_tuple_pattern_elements([left, %{kind: :tuple, elements: [mid, right]}]),
    do: [left, mid, right]

  defp flatten_tuple_pattern_elements(elems), do: elems

  defp bind_fun_arg(env, arg, loc) when is_binary(arg) do
    if simple_arg_name?(arg) do
      {t, env} = Env.fresh(env)
      {Env.put_value(env, arg, Env.mono(t)), t}
    else
      case Pattern.recover(arg) do
        {:ok, pat} ->
          bind_fun_pattern(env, pat, loc)

        :error ->
          {t, env} = Env.fresh(env)
          {env, t}
      end
    end
  end

  defp bind_fun_arg(env, arg, loc) when is_map(arg), do: bind_fun_pattern(env, arg, loc)

  defp bind_fun_arg(env, _arg, _loc) do
    {t, env} = Env.fresh(env)
    {env, t}
  end

  defp bind_fun_pattern(env, pat, loc) do
    {t, binds, _pat, env} = infer_pattern(env, pat, loc)

    env =
      Enum.reduce(binds, env, fn {name, type}, env ->
        Env.put_value(env, name, Env.mono(type))
      end)

    {env, t}
  end

  defp simple_arg_name?(name) do
    String.match?(name, ~r/^[a-z_][A-Za-z0-9_]*$/)
  end

  defp infer_subject(env, subject, loc), do: infer_expr(env, subject, loc)

  defp infer_value(env, value, loc), do: infer_expr(env, value, loc)

  defp instantiate_name(env, "()", expr, _loc), do: {:unit, expr, env}

  defp instantiate_name(env, name, expr, loc) do
    if is_binary(name) and not String.contains?(name, ".") and ambiguous_name?(env, name) do
      env =
        Env.add_error(
          env,
          Diagnostic.error(
            "ambiguous_import",
            "This usage of `#{name}` is ambiguous. It is imported from more than one module.",
            Keyword.put(loc, :name, name)
          )
        )

      {t, env} = Env.fresh(env)
      {t, expr, env}
    else
      instantiate_resolved_name(env, name, expr, loc)
    end
  end

  defp instantiate_resolved_name(env, name, expr, loc) do
    resolved = resolve_name(env, name)

    case lookup_scheme(env, name, resolved) do
      nil ->
        env =
          if not ambiguous_name?(env, name) and
               (unknown_should_error?(name) or unknown_should_error?(resolved)) do
            Env.add_error(
              env,
              Diagnostic.error("unbound_value", "I cannot find a `#{name}` variable",
                Keyword.put(loc, :name, name)
              )
            )
          else
            env
          end

        {t, env} = Env.fresh(env)
        {t, expr, env}

      {:forall, _, _} = scheme ->
        {t, env} = Env.instantiate(env, scheme)
        {t, expr, env}
    end
  end

  defp resolve_name(env, name) when is_binary(name) do
    ImportResolution.resolve(name, env.import_lookup)
  end

  defp resolve_name(_env, name), do: name

  defp lookup_scheme(env, name, resolved) do
    # Qualified `Alias.member` must prefer the alias target so
    # `import Pebble.Platform as Platform` + `Platform.worker` does not hit
    # elm/core `Platform.worker`. Bare names keep locals first so a lambda
    # `item_` is not shadowed by `Main.item_`.
    if is_binary(name) and String.contains?(name, ".") do
      Env.lookup_value(env, resolved) || Env.lookup_value(env, name) ||
        ctor_scheme(env, resolved) || ctor_scheme(env, name) ||
        operator_scheme(env, name)
    else
      Env.lookup_value(env, name) || Env.lookup_value(env, resolved) ||
        ctor_scheme(env, name) || ctor_scheme(env, resolved) ||
        operator_scheme(env, name)
    end
  end

  defp operator_scheme(env, name) when is_binary(name) do
    cond do
      String.starts_with?(name, "(") and String.ends_with?(name, ")") ->
        Env.lookup_value(env, name)

      name in [
        "+",
        "-",
        "*",
        "/",
        "//",
        "^",
        "==",
        "/=",
        "<",
        ">",
        "<=",
        ">=",
        "&&",
        "||",
        "++",
        "::",
        "<|",
        "|>",
        "<<",
        ">>"
      ] ->
        Env.lookup_value(env, "(#{name})")

      true ->
        nil
    end
  end

  defp lookup_or_fresh(env, "()", _loc), do: {:unit, env}

  defp lookup_or_fresh(env, name, loc) do
    resolved = resolve_name(env, name)

    case lookup_scheme(env, name, resolved) do
      nil ->
        if not ambiguous_name?(env, name) and
             (unknown_should_error?(name) or unknown_should_error?(resolved)) do
          env =
            Env.add_error(
              env,
              Diagnostic.error("unbound_value", "I cannot find a `#{name}` variable",
                Keyword.put(loc, :name, name)
              )
            )

          Env.fresh(env)
        else
          Env.fresh(env)
        end

      {:forall, _, _} = scheme ->
        Env.instantiate(env, scheme)
    end
  end

  defp ctor_scheme(env, name) do
    case Env.lookup_ctor(env, name) do
      nil -> nil
      info -> info.scheme
    end
  end

  defp four_plus_tuple_source?(source) when is_binary(source) do
    Regex.match?(~r/\([^()]*?,[^()]*?,[^()]*?,/s, source)
  end

  defp four_plus_tuple_source?(_), do: false

  defp check_value_cycle(env, name, args, expr, loc)
       when is_binary(name) and (args == [] or is_nil(args)) do
    if unguarded_self_ref?(name, expr, 0) do
      Env.add_error(
        env,
        Diagnostic.error(
          "value_cycle",
          "The value `#{name}` is defined in terms of itself. Recursive values must be functions.",
          Keyword.put(loc, :name, name)
        )
      )
    else
      env
    end
  end

  defp check_value_cycle(env, _name, _args, _expr, _loc), do: env

  defp unguarded_self_ref?(name, %{op: :lambda, body: body}, depth) do
    unguarded_self_ref?(name, body, depth + 1)
  end

  defp unguarded_self_ref?(expected, %{op: :var, name: got}, 0), do: expected == got
  defp unguarded_self_ref?(expected, %{op: :call, name: got}, 0), do: expected == got

  defp unguarded_self_ref?(name, %{op: op} = expr, 0)
       when op in [:add_vars, :sub_vars, :add_const, :sub_const] do
    Map.get(expr, :left) == name or Map.get(expr, :right) == name or Map.get(expr, :var) == name
  end

  defp unguarded_self_ref?(name, expr, depth) when is_map(expr) do
    Enum.any?(expr, fn
      {:op, _} -> false
      {:name, _} -> false
      {_, child} when is_map(child) -> unguarded_self_ref?(name, child, depth)
      {_, children} when is_list(children) ->
        Enum.any?(children, fn
          item when is_map(item) -> unguarded_self_ref?(name, item, depth)
          _ -> false
        end)

      _ ->
        false
    end)
  end

  defp unguarded_self_ref?(_name, _expr, _depth), do: false

  defp check_mutual_value_cycles(%FrontendModule{} = mod, env) do
    values =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function_definition and (&1.args || []) == []))
      |> Map.new(&{&1.name, &1})

    names = MapSet.new(Map.keys(values))

    graph =
      Map.new(values, fn {name, decl} ->
        {name, unguarded_refs(Map.get(decl, :expr), names, 0) |> MapSet.to_list()}
      end)

    Enum.reduce(names, env, fn name, env ->
      if cyclic_value?(graph, name, MapSet.new()) do
        Env.add_error(
          env,
          Diagnostic.error(
            "value_cycle",
            "The value `#{name}` is defined in terms of itself. Recursive values must be functions.",
            Keyword.put(loc(mod, name, values[name]), :name, name)
          )
        )
      else
        env
      end
    end)
  end

  defp unguarded_refs(expr, names, depth) do
    cond do
      not is_map(expr) ->
        MapSet.new()

      expr[:op] == :lambda ->
        unguarded_refs(Map.get(expr, :body), names, depth + 1)

      depth == 0 and is_binary(expr[:name]) and MapSet.member?(names, expr[:name]) and
          expr[:op] in [:var, :call] ->
        MapSet.new([expr[:name]])

      true ->
        Enum.reduce(expr, MapSet.new(), fn
          {_, child}, acc when is_map(child) ->
            MapSet.union(acc, unguarded_refs(child, names, depth))

          {_, children}, acc when is_list(children) ->
            Enum.reduce(children, acc, fn
              item, acc when is_map(item) -> MapSet.union(acc, unguarded_refs(item, names, depth))
              _, acc -> acc
            end)

          _, acc ->
            acc
        end)
    end
  end

  defp cyclic_value?(graph, name, seen) do
    cond do
      MapSet.member?(seen, name) ->
        true

      true ->
        seen = MapSet.put(seen, name)

        graph
        |> Map.get(name, [])
        |> Enum.any?(&cyclic_value?(graph, &1, seen))
    end
  end

  defp unknown_should_error?(name) when is_binary(name) do
    String.contains?(name, ".") or String.match?(name, ~r/^[a-zA-Z]/)
  end

  defp ambiguous_name?(env, name) when is_binary(name) do
    unqualified = Map.get(env.import_lookup, :import_unqualified_map, %{})
    Map.get(unqualified, name) == :ambiguous
  end

  defp unify_ok(env, a, b, loc) do
    case Solve.unify(env, a, b, loc) do
      {:ok, env} -> env
      {:error, env, _} -> env
    end
  end

  defp number_fresh(env, expr) do
    {t, env} = Env.fresh_constrained(env, :number)
    {t, expr, env}
  end

  defp apply_types(env, expr) when is_map(expr) do
    type =
      case Map.get(expr, :elm_type) do
        nil -> nil
        t -> Type.subst_apply(env.subst, t)
      end

    expr
    |> Map.put(:elm_type, type)
    |> Map.new(fn
      {:elm_type, _} -> {:elm_type, type}
      {k, v} when is_map(v) -> {k, apply_types(env, v)}
      {k, vs} when is_list(vs) -> {k, Enum.map(vs, &apply_types(env, &1))}
      pair -> pair
    end)
  end

  defp apply_types(_env, other), do: other

  defp field_name(%{name: name}), do: name
  defp field_name(%{field: name}), do: name
  defp field_name(_), do: "_"

  defp field_value(%{expr: expr}), do: expr
  defp field_value(%{value: expr}), do: expr
  defp field_value(other), do: other

  defp put_field_value(%{expr: _} = field, value), do: %{field | expr: value}
  defp put_field_value(%{value: _} = field, value), do: %{field | value: value}
  defp put_field_value(field, _value), do: field

  defp loc(mod, name, decl) do
    span = Map.get(decl, :span) || %{}

    [
      module: mod.name,
      function: name,
      file: Map.get(mod, :path),
      line: Map.get(span, :start_line)
    ]
  end
end
