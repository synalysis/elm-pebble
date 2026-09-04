defmodule ElmEx.Typesys.Solve do
  @moduledoc """
  Unification with occurs check and Elm constrained variables.
  """

  alias ElmEx.Typesys.{Diagnostic, Env, Type}

  @type unify_ok :: {:ok, Env.t()}
  @type unify_err :: {:error, Env.t(), Diagnostic.t()}

  @spec unify(Env.t(), Type.t(), Type.t(), keyword()) :: unify_ok() | unify_err()
  def unify(env, left, right, opts \\ []) do
    left = expand_type(env, Type.subst_apply(env.subst, left))
    right = expand_type(env, Type.subst_apply(env.subst, right))

    case do_unify(env, left, right) do
      {:ok, env} ->
        {:ok, env}

      {:error, env, reason} ->
        diag =
          Diagnostic.error(
            "type_mismatch",
            reason,
            Keyword.merge(opts,
              expected_type: Type.to_string(left),
              inferred_type: Type.to_string(right)
            )
          )

        {:error, Env.add_error(env, diag), diag}
    end
  end

  defp expand_type(env, type, seen \\ MapSet.new())

  defp expand_type(env, {:named, name, args}, seen) do
    args = Enum.map(args, &expand_type(env, &1, seen))

    if MapSet.member?(seen, name) do
      {:named, name, args}
    else
      case Env.lookup_alias(env, name) do
        %{body: body, params: params} when is_tuple(body) or body == :unit ->
          expand_type(env, apply_alias_params(body, params, args), MapSet.put(seen, name))

        %{body: body} when is_tuple(body) or body == :unit ->
          expand_type(env, apply_alias_params(body, [], args), MapSet.put(seen, name))

        _ ->
          {:named, name, args}
      end
    end
  end

  defp expand_type(env, {:fun, a, b}, seen),
    do: {:fun, expand_type(env, a, seen), expand_type(env, b, seen)}

  defp expand_type(env, {:tuple, elems}, seen),
    do: {:tuple, Enum.map(elems, &expand_type(env, &1, seen))}

  defp expand_type(env, {:record, fields, ext}, seen) do
    {:record, Map.new(fields, fn {k, v} -> {k, expand_type(env, v, seen)} end),
     if(ext, do: expand_type(env, ext, seen), else: nil)}
  end

  defp expand_type(_env, other, _seen), do: other

  defp apply_alias_params(body, params, args) when is_list(params) and params != [] do
    subst =
      params
      |> Enum.zip(args)
      |> Enum.reduce(%{}, fn {param, arg}, acc ->
        case param_var_id(param) do
          nil -> acc
          id -> Map.put(acc, id, arg)
        end
      end)

    Type.subst_apply(subst, body)
  end

  # `import Json.Decode exposing (Decoder)` used to install a 0-param synonym
  # whose body is `Json.Decode.Decoder`. Keep the type arguments.
  defp apply_alias_params({:named, name, []}, [], args) when is_list(args) and args != [] do
    {:named, name, args}
  end

  defp apply_alias_params(body, _params, _args), do: body

  defp param_var_id(id) when is_integer(id), do: id
  defp param_var_id({:var, id}), do: id
  defp param_var_id(name) when is_binary(name) do
    case ElmEx.Typesys.Parser.parse(name) do
      {:ok, {:var, id}} -> id
      _ -> nil
    end
  end

  defp param_var_id(_), do: nil

  defp do_unify(env, left, right) do
    left = expand_type(env, Type.subst_apply(env.subst, left))
    right = expand_type(env, Type.subst_apply(env.subst, right))
    unify_expanded(env, left, right)
  end

  defp unify_expanded(env, t, t), do: {:ok, env}

  defp unify_expanded(env, {:var, id}, other), do: bind(env, id, other)
  defp unify_expanded(env, other, {:var, id}), do: bind(env, id, other)

  defp unify_expanded(env, {:constrained, kind, id}, other) do
    bind_constrained(env, kind, id, other)
  end

  defp unify_expanded(env, other, {:constrained, kind, id}) do
    bind_constrained(env, kind, id, other)
  end

  defp unify_expanded(env, {:fun, a1, b1}, {:fun, a2, b2}) do
    with {:ok, env} <- do_unify(env, a1, a2) do
      do_unify(env, Type.subst_apply(env.subst, b1), Type.subst_apply(env.subst, b2))
    end
  end

  defp unify_expanded(env, {:tuple, xs}, {:tuple, ys}) when length(xs) == length(ys) do
    Enum.reduce_while(Enum.zip(xs, ys), {:ok, env}, fn {a, b}, {:ok, env} ->
      case do_unify(env, Type.subst_apply(env.subst, a), Type.subst_apply(env.subst, b)) do
        {:ok, env} -> {:cont, {:ok, env}}
        other -> {:halt, other}
      end
    end)
  end

  defp unify_expanded(env, {:named, n, as}, {:named, n, bs}) when length(as) == length(bs) do
    Enum.reduce_while(Enum.zip(as, bs), {:ok, env}, fn {a, b}, {:ok, env} ->
      case do_unify(env, Type.subst_apply(env.subst, a), Type.subst_apply(env.subst, b)) do
        {:ok, env} -> {:cont, {:ok, env}}
        other -> {:halt, other}
      end
    end)
  end

  defp unify_expanded(env, {:named, a, args}, {:named, b, args2}) do
    if same_named?(a, b) and length(args) == length(args2) do
      do_unify(env, {:named, a, args}, {:named, a, args2})
    else
      {:error, env, "Cannot unify #{Type.to_string({:named, a, args})} with #{Type.to_string({:named, b, args2})}"}
    end
  end

  defp unify_expanded(env, {:record, f1, e1}, {:record, f2, e2}) do
    unify_records(env, f1, e1, f2, e2)
  end

  defp unify_expanded(env, :unit, :unit), do: {:ok, env}

  defp unify_expanded(env, left, right) do
    {:error, env, "Cannot unify #{Type.to_string(left)} with #{Type.to_string(right)}"}
  end

  defp bind(env, id, {:var, id}), do: {:ok, env}

  defp bind(env, id, type) do
    type = Type.subst_apply(env.subst, type)

    cond do
      match?({:var, ^id}, type) ->
        {:ok, env}

      Env.rigid?(env, id) ->
        bind_rigid(env, id, type)

      match?({:var, _}, type) ->
        {:var, other} = type

        if Env.rigid?(env, other) do
          {:ok, %{env | subst: Map.put(env.subst, id, type)}}
        else
          bind_flex(env, id, type)
        end

      true ->
        bind_flex(env, id, type)
    end
  end

  defp bind_rigid(env, id, {:var, other}) do
    if Env.rigid?(env, other) and other != id do
      {:error, env, "Cannot unify distinct rigid type variables"}
    else
      {:ok, %{env | subst: Map.put(env.subst, other, Type.var(id))}}
    end
  end

  defp bind_rigid(env, _id, type) do
    {:error, env, "The type annotation is too general. I cannot unify a rigid type variable with #{Type.to_string(type)}"}
  end

  defp bind_flex(env, id, type) do
    cond do
      Type.occurs?(id, type) ->
        {:error, env, "Infinite type"}

      true ->
        {:ok, %{env | subst: Map.put(env.subst, id, type)}}
    end
  end

  defp bind_constrained(env, kind, id, type) do
    type = Type.subst_apply(env.subst, type)

    cond do
      match?({:var, ^id}, type) or match?({:constrained, _, ^id}, type) ->
        {:ok, env}

      match?({:var, _}, type) ->
        {:var, other} = type

        if Env.rigid?(env, other) do
          {:error, env, "#{kind} cannot instantiate a rigid type variable"}
        else
          {:ok, %{env | subst: Map.put(env.subst, other, Type.constrained(kind, id))}}
        end

      match?({:constrained, _, _}, type) ->
        {:constrained, other_kind, other_id} = type
        merged = merge_constraint(kind, other_kind)

        if merged do
          {:ok, %{env | subst: Map.put(env.subst, other_id, Type.constrained(merged, id))}}
        else
          {:error, env, "Cannot unify #{kind} with #{other_kind}"}
        end

      inhabits?(kind, type) ->
        bind(env, id, type)

      true ->
        {:error, env, "#{Type.to_string(type)} is not #{kind}"}
    end
  end

  defp merge_constraint(k, k), do: k
  defp merge_constraint(:number, :comparable), do: :number
  defp merge_constraint(:comparable, :number), do: :number
  defp merge_constraint(:appendable, :comparable), do: :compappend
  defp merge_constraint(:comparable, :appendable), do: :compappend
  defp merge_constraint(:compappend, _), do: :compappend
  defp merge_constraint(_, :compappend), do: :compappend
  defp merge_constraint(_, _), do: nil

  defp inhabits?(:number, {:named, name, []}) do
    short_named(name) in ["Int", "Float"]
  end

  defp inhabits?(:comparable, type), do: comparable?(type)

  defp inhabits?(:appendable, {:named, name, []}), do: short_named(name) == "String"
  defp inhabits?(:appendable, {:named, name, [_]}) when is_binary(name),
    do: short_named(name) == "List"

  defp inhabits?(:compappend, {:named, name, []}), do: short_named(name) == "String"
  defp inhabits?(:compappend, {:named, name, [elem]}) when is_binary(name),
    do: short_named(name) == "List" and comparable?(elem)

  defp inhabits?(_, _), do: false

  # Imported annotations qualify `String` as `String.String`. Constraint
  # inhabitants must use the last segment, same as `same_named?/2`.
  defp short_named(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp comparable?({:named, name, []}) do
    short_named(name) in ["Int", "Float", "Char", "String"]
  end

  defp comparable?({:named, name, [elem]}) when is_binary(name) do
    short_named(name) == "List" and comparable?(elem)
  end

  defp comparable?({:tuple, elems}), do: Enum.all?(elems, &comparable?/1)
  defp comparable?({:constrained, kind, _}) when kind in [:number, :comparable, :compappend], do: true
  defp comparable?(_), do: false

  defp same_named?(a, b) do
    a == b or
      (a in ["Cmd", "Platform.Cmd"] and b in ["Cmd", "Platform.Cmd"]) or
      (a in ["Sub", "Platform.Sub"] and b in ["Sub", "Platform.Sub"]) or
      html_node_name?(a) and html_node_name?(b) or
      html_attr_name?(a) and html_attr_name?(b) or
      String.ends_with?(a, "." <> b) or
      String.ends_with?(b, "." <> a)
  end

  # Official `Html.Html` is `VirtualDom.Node`; elm-css uses `VirtualDom.Styled.Node`.
  defp html_node_name?(name) when is_binary(name) do
    short_named(name) in ["Html", "Node"] and
      (name in ["Html", "Html.Html", "VirtualDom.Node", "VirtualDom.Styled.Node"] or
         String.ends_with?(name, ".Html") or String.ends_with?(name, ".Node"))
  end

  defp html_node_name?(_), do: false

  defp html_attr_name?(name) when is_binary(name) do
    short_named(name) == "Attribute" and
      (String.contains?(name, "Html") or String.contains?(name, "VirtualDom"))
  end

  defp html_attr_name?(_), do: false

  defp unify_records(env, f1, e1, f2, e2) do
    keys1 = MapSet.new(Map.keys(f1))
    keys2 = MapSet.new(Map.keys(f2))
    shared = MapSet.intersection(keys1, keys2)

    env_result =
      Enum.reduce_while(shared, {:ok, env}, fn key, {:ok, env} ->
        case do_unify(env, Type.subst_apply(env.subst, f1[key]), Type.subst_apply(env.subst, f2[key])) do
          {:ok, env} -> {:cont, {:ok, env}}
          other -> {:halt, other}
        end
      end)

    with {:ok, env} <- env_result do
      only1 = Map.drop(f1, MapSet.to_list(keys2))
      only2 = Map.drop(f2, MapSet.to_list(keys1))
      unify_rows(env, only1, e1, only2, e2)
    end
  end

  defp unify_rows(env, only1, e1, only2, e2) do
    cond do
      only1 == %{} and only2 == %{} ->
        case {e1, e2} do
          {nil, nil} -> {:ok, env}
          {nil, ext} -> if ext, do: do_unify(env, Type.record(%{}), ext), else: {:ok, env}
          {ext, nil} -> if ext, do: do_unify(env, ext, Type.record(%{})), else: {:ok, env}
          {a, b} -> do_unify(env, a || Type.record(%{}), b || Type.record(%{}))
        end

      only2 != %{} and e1 != nil ->
        {fresh, env} = Env.fresh(env)
        with {:ok, env} <- do_unify(env, e1, Type.record(only2, fresh)) do
          unify_rows(env, only1, fresh, %{}, e2)
        end

      only1 != %{} and e2 != nil ->
        {fresh, env} = Env.fresh(env)
        with {:ok, env} <- do_unify(env, e2, Type.record(only1, fresh)) do
          unify_rows(env, %{}, e1, only2, fresh)
        end

      only1 == %{} and only2 == %{} ->
        {:ok, env}

      true ->
        missing = Map.keys(only1)
        extra = Map.keys(only2)

        reason =
          cond do
            missing != [] and extra == [] ->
              "This record is missing the fields: #{Enum.join(Enum.sort(missing), ", ")}"

            extra != [] and missing == [] ->
              "This record has extra fields: #{Enum.join(Enum.sort(extra), ", ")}"

            true ->
              "Record fields do not match: #{Enum.join(Enum.sort(missing ++ extra), ", ")}"
          end

        {:error, env, reason}
    end
  end
end
