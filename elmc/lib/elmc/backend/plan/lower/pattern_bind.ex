defmodule Elmc.Backend.Plan.Lower.PatternBind do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Expr, Record}
  alias ElmEx.IR.TypeSignature

  @spec bind(Types.pattern(), Context.t(), Builder.t(), integer()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported
  def bind(pattern, ctx, b, subject_reg) when is_map(pattern) and is_integer(subject_reg) do
    do_bind(pattern, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :qualified_constructor} = pattern, ctx, b, subject_reg) do
    normalized =
      pattern
      |> Map.put(:kind, :constructor)
      |> Map.put_new(:resolved_name, Map.get(pattern, :name))

    do_bind(normalized, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :wildcard}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :int}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :string}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :char}, ctx, b, _subject_reg), do: {:ok, ctx, b}

  defp do_bind(%{kind: :var, name: name}, ctx, b, subject_reg) when is_binary(name) do
    ctx1 = Context.put_local(ctx, name, subject_reg)
    b1 = Builder.bind_local(b, name, subject_reg)

    case Context.letrec_ref(ctx, name) do
      ref when is_binary(ref) ->
        {_, b2} =
          Builder.emit(b1, :forward_ref_set, %{
            dest: nil,
            args: %{ref: ref, value: subject_reg},
            effects: Types.empty_effects()
          })

        {:ok, ctx1, b2}

      _ ->
        {:ok, ctx1, b1}
    end
  end

  defp do_bind(%{kind: :tuple, elements: elements}, ctx, b, subject_reg)
       when is_list(elements) and length(elements) > 2 do
    do_bind(%{kind: :tuple, elements: nest_tuple_elements(elements)}, ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :tuple, elements: [left, right]}, ctx, b, subject_reg) do
    with {:ok, ctx1, b1, _} <- bind_tuple_elem(left, :first, subject_reg, ctx, b),
         {:ok, ctx2, b2, _} <- bind_tuple_elem(right, :second, subject_reg, ctx1, b1) do
      {:ok, ctx2, b2}
    else
      _ -> :unsupported
    end
  end

  defp do_bind(%{kind: :record, fields: fields} = pattern, ctx, b, subject_reg)
       when is_list(fields) do
    bind = Map.get(pattern, :bind)

    {ctx0, b0} =
      if is_binary(bind) do
        {Context.put_local(ctx, bind, subject_reg), Builder.bind_local(b, bind, subject_reg)}
      else
        {ctx, b}
      end

    base_expr = if is_binary(bind), do: %{op: :var, name: bind}, else: nil

    Enum.with_index(fields)
    |> Enum.reduce_while({:ok, ctx0, b0}, fn {field_name, field_index}, {:ok, ctx_acc, b_acc}
                                            when is_binary(field_name) ->
      opts =
        if base_expr == nil do
          [index_override: field_index]
        else
          []
        end

      {:ok, field_reg, b1} =
        Record.emit_record_field_get(subject_reg, field_name, ctx_acc, b_acc, base_expr, opts)

      ctx1 = Context.put_local(ctx_acc, field_name, field_reg)
      b2 = Builder.bind_local(b1, field_name, field_reg)
      {:cont, {:ok, ctx1, b2}}
    end)
  end

  defp do_bind(
         %{kind: :constructor, name: name, arg_pattern: %{kind: :tuple, elements: [head, tail]}} =
           pattern,
         ctx,
         b,
         subject_reg
       )
       when is_binary(name) do
    {ctx, b} =
      case Map.get(pattern, :bind) do
        bind when is_binary(bind) ->
          ctx1 = enrich_constructor_bind_ctx(ctx, bind, pattern)
          {Context.put_local(ctx1, bind, subject_reg), Builder.bind_local(b, bind, subject_reg)}

        _ ->
          {ctx, b}
      end

    if cons_pattern?(pattern) do
      bind_cons_pattern(head, tail, subject_reg, ctx, b)
    else
      with {:ok, payload_reg, b1} <- emit_ctor_payload(pattern, subject_reg, ctx, b),
           {:ok, ctx1, b2} <-
             do_bind(%{kind: :tuple, elements: [head, tail]}, ctx, b1, payload_reg) do
        {:ok, ctx1, b2}
      else
        _ -> :unsupported
      end
    end
  end

  defp do_bind(%{kind: :constructor, resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}, ctx, b, subject_reg) do
    bind_cons_pattern(head, tail, subject_reg, ctx, b)
  end

  defp do_bind(%{kind: :constructor, bind: bind, arg_pattern: %{kind: :var, name: name}} = pattern, ctx, b, subject_reg)
       when is_binary(bind) do
    do_bind(Map.put(pattern, :arg_pattern, %{kind: :var, name: name}) |> Map.put(:bind, bind), ctx, b, subject_reg)
  end

  defp do_bind(%{kind: :constructor, bind: bind, arg_pattern: arg_pattern} = pattern, ctx, b, subject_reg)
       when is_binary(bind) and is_map(arg_pattern) do
    # Pattern like `Ctor ... as x` (or nested constructor bind slots) must bind
    # the full matched value, not only the payload.
    ctx1 = enrich_constructor_bind_ctx(ctx, bind, pattern)
    b1 = Builder.bind_local(b, bind, subject_reg)

    with {:ok, payload_reg, b2} <- emit_ctor_payload(pattern, subject_reg, ctx1, b1),
         {:ok, ctx2, b3} <- do_bind(arg_pattern, ctx1, b2, payload_reg) do
      {:ok, ctx2, b3}
    else
      _ -> :unsupported
    end
  end

  defp do_bind(%{kind: :constructor, arg_pattern: arg_pattern} = pattern, ctx, b, subject_reg)
       when is_map(arg_pattern) do
    with {:ok, payload_reg, b1} <- emit_ctor_payload(pattern, subject_reg, ctx, b),
         {:ok, ctx1, b2} <- do_bind(arg_pattern, ctx, b1, payload_reg) do
      {:ok, ctx1, b2}
    else
      _ -> :unsupported
    end
  end

  defp do_bind(%{kind: :constructor, bind: bind} = pattern, ctx, b, subject_reg)
       when is_binary(bind) do
    if is_nil(Map.get(pattern, :arg_pattern)) do
      {:ok, payload_reg, b1} = emit_ctor_payload(pattern, subject_reg, ctx, b)
      ctx1 = enrich_constructor_bind_ctx(ctx, bind, pattern)

      {:ok, Context.put_local(ctx1, bind, payload_reg), Builder.bind_local(b1, bind, payload_reg)}
    else
      {:ok, Context.put_local(ctx, bind, subject_reg), Builder.bind_local(b, bind, subject_reg)}
    end
  end

  # Nullary constructors only (`NoOp`, `Tick`, `Msg.A`, …). IR may omit
  # `arg_pattern` / `bind` instead of setting them to nil. Unary shorthand like
  # `BestLoaded value` binds the payload name in `:bind` and is handled above.
  defp do_bind(%{kind: :constructor} = pattern, ctx, b, _subject_reg) do
    if nullary_ctor_pattern?(pattern), do: {:ok, ctx, b}, else: :unsupported
  end

  defp do_bind(_, _ctx, _b, _subject_reg), do: :unsupported

  defp nullary_ctor_pattern?(pattern) do
    is_nil(Map.get(pattern, :arg_pattern)) and is_nil(Map.get(pattern, :bind))
  end

  defp bind_tuple_elem(%{kind: :wildcard}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :int}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :string}, _which, _base, ctx, b), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(pattern, which, base, ctx, b) do
    with {:ok, reg, b1} <- emit_tuple_proj(base, which, b),
         {:ok, ctx1, b2} <- do_bind(pattern, ctx, b1, reg) do
      {:ok, ctx1, b2, reg}
    else
      _ -> :unsupported
    end
  end

  defp emit_ctor_payload(pattern, subject_reg, ctx, b) do
    if just_ctor?(pattern) do
      emit_maybe_just_payload(subject_reg, ctx, b)
    else
      emit_union_payload(subject_reg, ctx, b)
    end
  end

  defp emit_tuple_proj(base_reg, which, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :tuple_proj, %{
        dest: dest,
        args: %{base: base_reg, which: which},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [base_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp emit_union_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:union_payload, [subject_reg], ctx, b)
  end

  defp emit_maybe_just_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:maybe_just_payload, [subject_reg], ctx, b)
  end

  defp just_ctor?(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)
    is_binary(name) and short_name(name) == "Just"
  end

  defp short_name(name), do: name |> String.split(".") |> List.last()

  defp cons_pattern?(%{name: name}) when is_binary(name), do: short_name(name) == "::"
  defp cons_pattern?(%{resolved_name: "List.::"}), do: true
  defp cons_pattern?(_), do: false

  defp bind_cons_pattern(head, tail, subject_reg, ctx, b) do
    with {:ok, head_maybe, b1} <- Expr.compile_runtime_builtin(:list_head, [subject_reg], ctx, b),
         {:ok, head_reg, b2} <- Expr.compile_runtime_builtin(:maybe_just_payload, [head_maybe], ctx, b1),
         {:ok, tail_maybe, b3} <- Expr.compile_runtime_builtin(:list_tail, [subject_reg], ctx, b2),
         {:ok, tail_reg, b4} <- Expr.compile_runtime_builtin(:maybe_just_payload, [tail_maybe], ctx, b3),
         {:ok, ctx1, b5} <- do_bind(head, ctx, b4, head_reg),
         {:ok, ctx2, b6} <- do_bind(tail, ctx1, b5, tail_reg) do
      {:ok, ctx2, b6}
    else
      _ -> :unsupported
    end
  end

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]

  defp enrich_constructor_bind_ctx(ctx, bind, pattern) when is_binary(bind) do
    case constructor_payload_spec(pattern, ctx) do
      spec when is_binary(spec) ->
        ctx
        |> Context.put_local_type(bind, spec)
        |> maybe_put_inferred_param_fields(bind, spec)

      _ ->
        ctx
    end
  end

  defp maybe_put_inferred_param_fields(ctx, bind, spec) when is_binary(bind) and is_binary(spec) do
    if TypeSignature.record_type?(spec) do
      fields =
        spec
        |> TypeSignature.record_field_names()
        |> Enum.map(&to_string/1)
        |> Enum.sort()

      %{ctx | inferred_param_fields: Map.put(ctx.inferred_param_fields || %{}, bind, fields)}
    else
      ctx
    end
  end

  defp constructor_payload_spec(pattern, ctx) do
    specs = Process.get(:elmc_union_constructor_payload_specs, %{})
    mod = ctx.module

    [Map.get(pattern, :resolved_name), Map.get(pattern, :name)]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn name ->
      short = short_name(name)
      [{mod, name}, {mod, short}]
    end)
    |> Enum.uniq()
    |> Enum.find_value(fn key -> Map.get(specs, key) end)
  end
end
