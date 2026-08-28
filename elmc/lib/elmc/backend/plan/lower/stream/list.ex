defmodule Elmc.Backend.Plan.Lower.Stream.List do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.{Expr, Lambda}
  alias Elmc.Backend.Plan.Stream

  @max_unroll 64

  @map_names MapSet.new(["map", "concatMap", "indexedMap"])
  @concat_names MapSet.new(["concat"])
  @cons_names MapSet.new(["cons", "::"])
  @append_names MapSet.new(["append", "++", "__append__"])
  @filter_names MapSet.new(["filter"])
  @list_modules MapSet.new(["List", "Elm.Kernel.List"])
  @append_modules MapSet.new(["List", "Elm.Kernel.List", "Basics"])
  @range_names MapSet.new(["range"])

  @runtime_kind %{
    "elmc_list_map" => :map,
    "elmc_list_concat_map" => :concat_map,
    "elmc_list_indexed_map" => :indexed_map
  }

  @spec map_call?(map(), String.t() | nil) :: boolean()
  def map_call?(expr, module) when is_map(expr) do
    case Stream.callee_key(expr, module) do
      {mod, name} -> MapSet.member?(@list_modules, mod) and MapSet.member?(@map_names, name)
      _ -> false
    end
  end

  def map_call?(_, _), do: false

  @spec concat_call?(map(), String.t() | nil) :: boolean()
  def concat_call?(expr, module) when is_map(expr) do
    case Stream.callee_key(expr, module) do
      {mod, name} -> MapSet.member?(@list_modules, mod) and MapSet.member?(@concat_names, name)
      _ -> false
    end
  end

  def concat_call?(_, _), do: false

  @spec cons_target?(String.t()) :: boolean()
  def cons_target?(target) when is_binary(target) do
    case Stream.callee_key(%{op: :qualified_call, target: target}, nil) do
      {mod, name} ->
        MapSet.member?(@cons_names, name) and
          (MapSet.member?(@list_modules, mod) or name == "::")

      _ ->
        target in ["::", "List.::"]
    end
  end

  def cons_target?(_), do: false

  @spec cons_call?(map(), String.t() | nil) :: boolean()
  def cons_call?(expr, module) when is_map(expr) do
    case Stream.callee_key(expr, module) do
      {_mod, name} -> MapSet.member?(@cons_names, name)
      _ -> false
    end
  end

  def cons_call?(_, _), do: false

  def append_call?(expr, module) when is_map(expr) do
    case Stream.callee_key(expr, module) do
      {mod, name} ->
        MapSet.member?(@append_names, name) and
          (name in ["++", "__append__"] or MapSet.member?(@append_modules, mod))

      _ ->
        false
    end
  end

  def append_call?(_, _), do: false

  @spec eligible_append_call?(map(), map(), String.t() | nil, MapSet.t(), MapSet.t()) :: boolean()
  def eligible_append_call?(expr, decl_map, module, seen, locals \\ MapSet.new())

  def eligible_append_call?(expr, decl_map, module, seen, locals) when is_map(expr) do
    case Map.get(expr, :args, []) do
      [left, right] ->
        Stream.eligible_expr?(left, decl_map, module, seen, locals) and
          Stream.eligible_expr?(right, decl_map, module, seen, locals)

      _ ->
        false
    end
  end

  def eligible_append_call?(_, _, _, _, _), do: false

  @spec eligible_cons_call?(map(), map(), String.t() | nil, MapSet.t(), MapSet.t()) :: boolean()
  def eligible_cons_call?(expr, decl_map, module, seen, locals \\ MapSet.new())

  def eligible_cons_call?(expr, decl_map, module, seen, locals) when is_map(expr) do
    case Map.get(expr, :args, []) do
      [head, tail] ->
        Stream.eligible_expr?(head, decl_map, module, seen, locals) and
          Stream.eligible_expr?(tail, decl_map, module, seen, locals)

      _ ->
        false
    end
  end

  def eligible_cons_call?(_, _, _, _, _), do: false

  @spec eligible_concat_call?(map(), map(), String.t() | nil, MapSet.t(), MapSet.t()) :: boolean()
  def eligible_concat_call?(expr, decl_map, module, seen, locals \\ MapSet.new())

  def eligible_concat_call?(expr, decl_map, module, seen, locals) when is_map(expr) do
    case Map.get(expr, :args, []) do
      [lists] -> Stream.eligible_expr?(lists, decl_map, module, seen, locals)
      _ -> false
    end
  end

  def eligible_concat_call?(_, _, _, _, _), do: false

  @spec expandable_source?(term()) :: boolean()
  def expandable_source?(expr), do: expand_source(expr) != :error

  @spec eligible_map_call?(map(), map(), String.t() | nil, MapSet.t()) :: boolean()
  def eligible_map_call?(expr, decl_map, module, seen) when is_map(expr) do
    args = Map.get(expr, :args, [])

    case {Stream.callee_key(expr, module), args} do
      {{mod, name}, [fun, list]}
      when mod in ["List", "Elm.Kernel.List"] and name in ["map", "concatMap"] ->
        mapper_eligible?(fun, decl_map, module, seen) and source_eligible?(fun, list)

      {{mod, "indexedMap"}, [fun, list]} when mod in ["List", "Elm.Kernel.List"] ->
        mapper_eligible?(fun, decl_map, module, seen) and source_eligible?(fun, list)

      _ ->
        false
    end
  end

  def eligible_map_call?(_, _, _, _), do: false

  @spec try_compile_call(String.t() | nil, [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def try_compile_call(target, args, ctx, b) when is_binary(target) and is_list(args) do
    key = Stream.callee_key(%{op: :qualified_call, target: target}, ctx.module)
    compile_key(key, args, ctx, b)
  end

  def try_compile_call(_, _, _, _), do: :unsupported

  @spec try_compile_runtime(map(), Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def try_compile_runtime(%{function: "elmc_list_concat", args: [lists]}, ctx, b) do
    compile_concat(lists, ctx, b)
  end

  def try_compile_runtime(%{function: "elmc_list_cons", args: [head, tail]}, ctx, b) do
    compile_cons(head, tail, ctx, b)
  end

  def try_compile_runtime(%{function: function, args: [fun, list]}, ctx, b)
      when is_binary(function) do
    case Map.get(@runtime_kind, function) do
      nil -> :unsupported
      kind -> compile_kind(kind, fun, list, ctx, b)
    end
  end

  def try_compile_runtime(_, _, _), do: :unsupported

  @spec compile([Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def compile([], _ctx, b), do: {:ok, :stream_void, b}

  def compile(items, ctx, b) when is_list(items) do
    arm_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(items, {:ok, :stream_void, b}, fn item, {:ok, :stream_void, b_acc} ->
      case Expr.compile(item, arm_ctx, b_acc) do
        {:ok, :stream_void, b1} -> {:cont, {:ok, :stream_void, b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  @spec compile_append(Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def compile_append(left, right, ctx, b) do
    with {:ok, :stream_void, b1} <- compile_expr(left, ctx, b),
         {:ok, :stream_void, b2} <- compile_expr(right, ctx, b1) do
      {:ok, :stream_void, b2}
    else
      _ -> :unsupported
    end
  end

  @spec compile_cons(Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def compile_cons(head, tail, ctx, b) do
    with {:ok, :stream_void, b1} <- compile_expr(head, ctx, b),
         {:ok, :stream_void, b2} <- compile_expr(tail, ctx, b1) do
      {:ok, :stream_void, b2}
    else
      _ -> :unsupported
    end
  end

  defp compile_expr(expr, ctx, b) do
    case expr do
      %{op: :list_literal, items: items} -> compile(items, ctx, b)
      %{op: :list_literal, elements: items} -> compile(items, ctx, b)
      _ -> Expr.compile(expr, ctx, b)
    end
  end

  defp compile_key({mod, name}, [fun, list], ctx, b)
       when mod in ["List", "Elm.Kernel.List"] and name in ["map", "concatMap"] do
    kind = if name == "concatMap", do: :concat_map, else: :map
    compile_kind(kind, fun, list, ctx, b)
  end

  defp compile_key({mod, "indexedMap"}, [fun, list], ctx, b)
       when mod in ["List", "Elm.Kernel.List"] do
    compile_kind(:indexed_map, fun, list, ctx, b)
  end

  defp compile_key({mod, "concat"}, [lists], ctx, b)
       when mod in ["List", "Elm.Kernel.List"] do
    compile_concat(lists, ctx, b)
  end

  defp compile_key({_mod, name}, [head, tail], ctx, b) when name in ["cons", "::"] do
    compile_cons(head, tail, ctx, b)
  end

  defp compile_key({_mod, name}, [left, right], ctx, b)
       when name in ["append", "++", "__append__"] do
    compile_append(left, right, ctx, b)
  end

  defp compile_key(_, _, _, _), do: :unsupported

  defp compile_concat(lists, ctx, b) do
    case compile_expr(lists, ctx, b) do
      {:ok, :stream_void, b1} -> {:ok, :stream_void, b1}
      _ -> :unsupported
    end
  end

  defp compile_kind(kind, fun, list, ctx, b) do
    list = resolve_stream_expr(list, ctx)

    case expand_source(list) do
      {:ok, items} ->
        case mapper_spec(fun, kind == :indexed_map) do
          {:ok, mapper} -> unroll(mapper, items, kind == :indexed_map, ctx, b)
          :error -> :unsupported
        end

      :error ->
        compile_foreach(kind, fun, list, ctx, b)
    end
  end

  defp compile_foreach(kind, fun, list, ctx, b) do
    value_ctx = value_ctx(ctx)

    with {:ok, list_reg, b1} <- Expr.compile(list, value_ctx, b),
         true <- is_integer(list_reg) do
      case mapper_spec(fun, kind == :indexed_map) do
        {:ok, {:apply, apply_fun}} ->
          compile_foreach_apply(kind, apply_fun, list_reg, value_ctx, ctx, b1)

        {:ok, {:lambda, _, _}} ->
          compile_foreach_lambda(kind, fun, list_reg, ctx, b1)

        _ ->
          :unsupported
      end
    else
      _ -> :unsupported
    end
  end

  defp compile_foreach_apply(kind, apply_fun, list_reg, value_ctx, ctx, b) do
    with {:ok, mod, name, prefix_exprs} <- apply_callee(apply_fun, ctx),
         {:ok, prefix_regs, b1} <- Expr.compile_args(prefix_exprs, value_ctx, b) do
      emit_stream_for_each(
        %{
          list: list_reg,
          prefix: prefix_regs,
          module: mod,
          name: name,
          indexed?: kind == :indexed_map
        },
        ctx,
        b1
      )
    else
      _ -> :unsupported
    end
  end

  defp compile_foreach_lambda(kind, fun, list_reg, ctx, b) do
    case Lambda.compile_for_stream_each(fun, ctx, b) do
      {:ok, idx, capture_regs, b1} ->
        emit_stream_for_each(
          %{
            list: list_reg,
            prefix: capture_regs,
            captures: capture_regs,
            lambda_idx: idx,
            indexed?: kind == :indexed_map
          },
          ctx,
          b1
        )

      _ ->
        :unsupported
    end
  end

  defp emit_stream_for_each(args, ctx, b) when is_map(args) do
    list_reg = args.list
    prefix_regs = List.wrap(Map.get(args, :prefix, []))
    borrow = Enum.uniq([list_reg | prefix_regs])
    effects = %{produces: nil, consumes: [], borrows: borrow, fallible: true}
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {_, b2} =
      Builder.emit(b1, :stream_for_each, %{
        dest: :stream_void,
        args: args,
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2
    {:ok, :stream_void, b3}
  end

  defp apply_callee(%{op: :var, name: name}, ctx) when is_binary(name),
    do: {:ok, ctx.module, name, []}

  defp apply_callee(%{op: :qualified_ref, target: target}, ctx) when is_binary(target) do
    case Stream.callee_key(%{op: :qualified_call, target: target}, ctx.module) do
      {mod, name} -> {:ok, mod, name, []}
      _ -> :error
    end
  end

  defp apply_callee(%{op: op} = fun, ctx) when op in [:call, :qualified_call] do
    case Stream.callee_key(fun, ctx.module) do
      {mod, name} -> {:ok, mod, name, List.wrap(Map.get(fun, :args))}
      _ -> :error
    end
  end

  defp apply_callee(_, _), do: :error

  defp expand_source(expr) do
    cond do
      match?(%{op: :list_literal, items: items} when is_list(items), expr) ->
        take_unroll(expr.items)

      match?(%{op: :list_literal, elements: items} when is_list(items), expr) ->
        take_unroll(expr.elements)

      range_bounds(expr) != :error ->
        {:ok, lo, hi} = range_bounds(expr)
        expand_range(lo, hi)

      append_parts(expr) != :error ->
        {:ok, left, right} = append_parts(expr)

        with {:ok, left_items} <- expand_source(left),
             {:ok, right_items} <- expand_source(right) do
          take_unroll(left_items ++ right_items)
        else
          _ -> :error
        end

      map_parts(expr) != :error ->
        {:ok, fun, src} = map_parts(expr)

        with {:ok, items} <- expand_source(src),
             {:ok, mapped} <- map_expand_items(fun, items) do
          take_unroll(mapped)
        else
          _ -> :error
        end

      filter_parts(expr) != :error ->
        {:ok, pred, src} = filter_parts(expr)

        with {:ok, items} <- expand_source(src),
             {:ok, kept} <- filter_expand_items(pred, items) do
          take_unroll(kept)
        else
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp resolve_stream_expr(%{op: :var, name: name} = expr, ctx) when is_binary(name) do
    case Context.stream_alias(ctx, name) do
      %{} = aliased -> resolve_stream_expr(aliased, ctx)
      _ -> expr
    end
  end

  defp resolve_stream_expr(%{args: [left, right]} = expr, ctx) do
    case append_parts(expr) do
      {:ok, _, _} ->
        %{expr | args: [resolve_stream_expr(left, ctx), resolve_stream_expr(right, ctx)]}

      :error ->
        expr
    end
  end

  defp resolve_stream_expr(expr, _ctx), do: expr

  defp map_parts(expr) when is_map(expr) do
    case Stream.callee_key(expr, nil) do
      {mod, "map"} ->
        if MapSet.member?(@list_modules, mod) do
          case Map.get(expr, :args) do
            [fun, list] -> {:ok, fun, list}
            _ -> :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp map_parts(_), do: :error

  defp filter_parts(expr) when is_map(expr) do
    case Stream.callee_key(expr, nil) do
      {mod, name} ->
        if MapSet.member?(@list_modules, mod) and MapSet.member?(@filter_names, name) do
          case Map.get(expr, :args) do
            [pred, list] -> {:ok, pred, list}
            _ -> :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp filter_parts(_), do: :error

  defp map_expand_items(%{op: :lambda, args: [param], body: body}, items) when is_binary(param) do
    {:ok, Enum.map(items, &subst_var(body, param, &1))}
  end

  defp map_expand_items(_, _), do: :error

  defp filter_expand_items(%{op: :lambda, args: [param], body: body}, items)
       when is_binary(param) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case eval_int_pred(body, param, item) do
        {:ok, true} -> {:cont, {:ok, acc ++ [item]}}
        {:ok, false} -> {:cont, {:ok, acc}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp filter_expand_items(_, _), do: :error

  defp eval_int_pred(body, param, %{op: :int_literal, value: n}) when is_integer(n) do
    case mod_by_eq_pred(body, param) do
      {:ok, base, rem} when base > 0 -> {:ok, Integer.mod(n, base) == rem}
      _ -> :error
    end
  end

  defp eval_int_pred(_, _, _), do: :error

  defp mod_by_eq_pred(body, param) do
    case eq_int_sides(body) do
      {:ok, left, rem} ->
        case mod_by_base(left, param) do
          {:ok, base} -> {:ok, base, rem}
          :error -> :error
        end

      :error ->
        :error
    end
  end

  defp eq_int_sides(%{op: :call, name: name, args: [left, right]})
       when name in ["__eq__", "==", "eq"] do
    eq_int_pair(left, right)
  end

  defp eq_int_sides(%{op: :compare, kind: :eq, left: left, right: right}),
    do: eq_int_pair(left, right)

  defp eq_int_sides(%{op: :qualified_call, args: [left, right]} = expr) do
    case Stream.callee_key(expr, nil) do
      {_, name} when name in ["__eq__", "==", "eq"] -> eq_int_pair(left, right)
      _ -> :error
    end
  end

  defp eq_int_sides(_), do: :error

  defp eq_int_pair(left, right) do
    case {literal_int(left), literal_int(right)} do
      {:error, {:ok, rem}} -> {:ok, left, rem}
      {{:ok, rem}, :error} -> {:ok, right, rem}
      _ -> :error
    end
  end

  defp mod_by_base(%{op: :call, name: "modBy", args: [base, %{op: :var, name: param}]}, param) do
    literal_int(base)
  end

  defp mod_by_base(%{op: :qualified_call, args: [base, %{op: :var, name: param}]} = expr, param) do
    case Stream.callee_key(expr, nil) do
      {mod, "modBy"} when mod in ["Basics", "Elm.Kernel.Basics"] -> literal_int(base)
      _ -> :error
    end
  end

  defp mod_by_base(
         %{op: :runtime_call, function: "elmc_basics_mod_by", args: [base, %{op: :var, name: param}]},
         param
       ),
       do: literal_int(base)

  defp mod_by_base(_, _), do: :error

  defp subst_var(%{op: :var, name: name}, name, replacement), do: replacement

  defp subst_var(expr, name, replacement) when is_map(expr) do
    Enum.reduce(expr, %{}, fn
      {:args, args}, acc when is_list(args) ->
        Map.put(acc, :args, Enum.map(args, &subst_var(&1, name, replacement)))

      {:fields, fields}, acc when is_list(fields) ->
        Map.put(
          acc,
          :fields,
          Enum.map(fields, fn
            %{expr: inner} = field when is_map(inner) ->
              Map.put(field, :expr, subst_var(inner, name, replacement))

            field ->
              field
          end)
        )

      {:body, body}, acc when is_map(body) ->
        Map.put(acc, :body, subst_var(body, name, replacement))

      {:items, items}, acc when is_list(items) ->
        Map.put(acc, :items, Enum.map(items, &subst_var(&1, name, replacement)))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp subst_var(other, _, _), do: other

  defp take_unroll(items) when length(items) <= @max_unroll, do: {:ok, items}
  defp take_unroll(_), do: :error

  defp expand_range(lo, hi) when hi < lo, do: {:ok, []}

  defp expand_range(lo, hi) when hi - lo + 1 <= @max_unroll do
    {:ok, Enum.map(lo..hi, fn n -> %{op: :int_literal, value: n} end)}
  end

  defp expand_range(_, _), do: :error

  defp range_bounds(%{op: op, args: [lo, hi]} = expr) when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {mod, name} ->
        if MapSet.member?(@list_modules, mod) and MapSet.member?(@range_names, name) do
          case {literal_int(lo), literal_int(hi)} do
            {{:ok, a}, {:ok, b}} -> {:ok, a, b}
            _ -> :error
          end
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp range_bounds(%{op: :runtime_call, function: "elmc_list_range", args: [lo, hi]}) do
    case {literal_int(lo), literal_int(hi)} do
      {{:ok, a}, {:ok, b}} -> {:ok, a, b}
      _ -> :error
    end
  end

  defp range_bounds(_), do: :error

  defp append_parts(%{op: :call, name: "__append__", args: [left, right]}),
    do: {:ok, left, right}

  defp append_parts(%{op: op, args: [left, right]} = expr)
       when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {mod, "append"} when mod in ["List", "Elm.Kernel.List"] -> {:ok, left, right}
      _ -> :error
    end
  end

  defp append_parts(_), do: :error

  defp literal_int(%{op: :int_literal, value: v}) when is_integer(v), do: {:ok, v}
  defp literal_int(_), do: :error

  defp mapper_spec(%{op: :lambda, args: [param], body: body}, false) when is_binary(param),
    do: {:ok, {:lambda, [param], body}}

  defp mapper_spec(%{op: :lambda, args: [i, item], body: body}, true)
       when is_binary(i) and is_binary(item),
       do: {:ok, {:lambda, [i, item], body}}

  defp mapper_spec(%{op: op} = fun, _indexed?)
       when op in [:call, :qualified_call, :var, :qualified_ref],
       do: {:ok, {:apply, fun}}

  defp mapper_spec(_, _), do: :error

  defp unroll(mapper, items, indexed?, ctx, b) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, :stream_void, b}, fn {item, index}, {:ok, :stream_void, acc} ->
      case apply_mapper(mapper, item, index, indexed?, ctx, acc) do
        {:ok, :stream_void, b1} -> {:cont, {:ok, :stream_void, b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp apply_mapper({:lambda, params, body}, item, index, indexed?, ctx, b) do
    value_ctx = value_ctx(ctx)

    with {:ok, item_reg, b1} <- Expr.compile(item, value_ctx, b) do
      ctx1 = Context.put_local(ctx, List.last(params), item_reg)

      ctx2 =
        if indexed? and match?([_, _], params) do
          case Expr.compile(%{op: :int_literal, value: index}, value_ctx, b1) do
            {:ok, idx_reg, b2} ->
              {Context.put_local(ctx1, hd(params), idx_reg), b2}

            _ ->
              :error
          end
        else
          {ctx1, b1}
        end

      case ctx2 do
        {bound, b_bound} -> Expr.compile(body, bound, b_bound)
        :error -> :unsupported
      end
    else
      _ -> :unsupported
    end
  end

  defp apply_mapper({:apply, fun}, item, index, indexed?, ctx, b) do
    extra = if indexed?, do: [%{op: :int_literal, value: index}, item], else: [item]
    Expr.compile(append_call_args(fun, extra), ctx, b)
  end

  defp append_call_args(%{op: :var, name: name}, extra),
    do: %{op: :call, name: name, args: extra}

  defp append_call_args(%{op: op} = fun, extra) when op in [:call, :qualified_call] do
    Map.put(fun, :args, List.wrap(Map.get(fun, :args)) ++ extra)
  end

  defp value_ctx(ctx), do: %{Context.for_branch_arm(ctx) | stream_mode: false}

  # Mapper bodies are often `Pebble.Ui.rect` etc. that become `:render_cmd`
  # only during compile. Require a callable shape; stream compile decides.
  defp mapper_eligible?(%{op: :lambda}, _, _, _), do: true

  defp mapper_eligible?(%{op: op}, _, _, _)
       when op in [:call, :qualified_call, :var, :qualified_ref],
       do: true

  defp mapper_eligible?(_, _, _, _), do: false

  defp source_eligible?(fun, list) do
    expand_source(list) != :error or
      (value_list_source?(list) and foreach_mapper_shape?(fun))
  end

  defp foreach_mapper_shape?(%{op: op})
       when op in [:call, :qualified_call, :var, :qualified_ref, :lambda],
       do: true

  defp foreach_mapper_shape?(_), do: false

  defp value_list_source?(%{op: op})
       when op in [
              :var,
              :field_access,
              :record_get,
              :record_get_int,
              :call,
              :qualified_call,
              :runtime_call,
              :list_literal,
              :let_in,
              :if,
              :case
            ],
       do: true

  defp value_list_source?(_), do: false
end
