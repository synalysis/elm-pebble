defmodule Elmc.Backend.Plan.Lower.PatternBind do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Expr, Record}
  alias ElmEx.IR.TypeSignature

  @spec bind(Types.pattern(), Context.t(), Builder.t(), integer()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported
  def bind(pattern, ctx, b, subject_reg) when is_map(pattern) and is_integer(subject_reg) do
    do_bind(pattern, ctx, b, subject_reg)
  end

  @spec do_bind(Types.pattern() | term(), Context.t(), Builder.t(), Types.reg()) ::
          {:ok, Context.t(), Builder.t()} | :unsupported

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

  defp do_bind(%{kind: :tuple, elements: [left, right]} = pattern, ctx, b, subject_reg) do
    {ctx0, b0} =
      case Map.get(pattern, :bind) do
        bind when is_binary(bind) ->
          {Context.put_local(ctx, bind, subject_reg), Builder.bind_local(b, bind, subject_reg)}

        _ ->
          {ctx, b}
      end

    elem_types = tuple_elem_types_for_reg(ctx0, subject_reg)

    with {:ok, ctx1, b1, _} <-
           bind_tuple_elem(left, :first, subject_reg, ctx0, b0, Enum.at(elem_types, 0)),
         {:ok, ctx2, b2, _} <-
           bind_tuple_elem(right, :second, subject_reg, ctx1, b1, Enum.at(elem_types, 1)) do
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

    # Pattern field lists follow source/destructure order, not runtime layout.
    # Named aliases keep declaration order (via elmc_record_alias_shapes); anonymous
    # records (Color.toRgba, etc.) are alphabetical like Elm. Never use Enum.with_index
    # on the IR pattern list — that scrambled View {title,body} and rgba alike.
    field_index_by_name = record_pattern_field_indices(fields)

    Enum.reduce_while(fields, {:ok, ctx0, b0}, fn field_name, {:ok, ctx_acc, b_acc}
                                                 when is_binary(field_name) ->
      opts =
        if base_expr == nil do
          [index_override: Map.fetch!(field_index_by_name, field_name)]
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
    # `Types.Light first` binds the payload in arg_pattern (no outer `:bind`).
    # Attach the union payload record type so field indices use Light layout
    # (x@6, …), not a min-index fallback across unrelated shapes.
    ctx0 = maybe_enrich_payload_arg_ctx(ctx, arg_pattern, pattern)

    with {:ok, payload_reg, b1} <- emit_ctor_payload(pattern, subject_reg, ctx0, b),
         {:ok, ctx1, b2} <- do_bind(arg_pattern, ctx0, b1, payload_reg) do
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

  # Prefer a unique registered shape for this field set; else Elm alphabetical layout.
  @spec record_pattern_field_indices(list()) :: %{String.t() => non_neg_integer()}

  defp record_pattern_field_indices(fields) when is_list(fields) do
    names = Enum.map(fields, &to_string/1)
    sorted = Enum.sort(names)

    shape =
      case unique_registered_shape_for_fields(sorted) do
        {:ok, registered} -> registered
        :none -> sorted
      end

    shape
    |> Enum.with_index()
    |> Map.new()
  end

  @spec unique_registered_shape_for_fields([String.t()]) :: {:ok, [String.t()]} | :none

  defp unique_registered_shape_for_fields(sorted_names) when is_list(sorted_names) do
    shapes =
      Process.get(:elmc_record_alias_shapes, %{})
      |> Map.merge(Process.get(:elmc_inline_record_literal_shapes, %{}))
      |> Map.values()
      |> Enum.filter(&(is_list(&1) and &1 != []))
      |> Enum.map(fn shape -> Enum.map(shape, &to_string/1) end)
      |> Enum.filter(fn shape -> Enum.sort(shape) == sorted_names end)
      |> Enum.uniq()

    case shapes do
      [shape] ->
        {:ok, shape}

      [] ->
        :none

      many ->
        # Prefer declaration-order alias when it is the unique non-alphabetical layout;
        # otherwise Elm alphabetical (anonymous literals / union payloads).
        alpha = sorted_names

        case Enum.reject(many, &(&1 == alpha)) do
          [decl] -> {:ok, decl}
          _ -> {:ok, alpha}
        end
    end
  end

  @spec nullary_ctor_pattern?(Types.pattern()) :: boolean()

  defp nullary_ctor_pattern?(pattern) do
    is_nil(Map.get(pattern, :arg_pattern)) and is_nil(Map.get(pattern, :bind))
  end

  @spec bind_tuple_elem(
          Types.pattern(),
          atom(),
          Types.reg(),
          Context.t(),
          Builder.t(),
          String.t() | nil
        ) :: {:ok, Context.t(), Builder.t(), Types.reg() | nil} | :unsupported

  defp bind_tuple_elem(%{kind: :wildcard}, _which, _base, ctx, b, _elem_type),
    do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :int}, _which, _base, ctx, b, _elem_type), do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(%{kind: :string}, _which, _base, ctx, b, _elem_type),
    do: {:ok, ctx, b, nil}

  defp bind_tuple_elem(pattern, which, base, ctx, b, elem_type) do
    with {:ok, reg, b1} <- emit_tuple_proj(base, which, b),
         ctx_typed <- maybe_put_tuple_elem_type(ctx, pattern, elem_type),
         {:ok, ctx1, b2} <- do_bind(pattern, ctx_typed, b1, reg) do
      {:ok, ctx1, b2, reg}
    else
      _ -> :unsupported
    end
  end

  @spec maybe_put_tuple_elem_type(Context.t(), Types.pattern() | term(), String.t() | nil) ::
          Context.t()

  defp maybe_put_tuple_elem_type(ctx, %{kind: :var, name: name}, type)
       when is_binary(name) and is_binary(type) and type != "" do
    Context.put_local_type(ctx, name, type)
  end

  defp maybe_put_tuple_elem_type(ctx, _pattern, _type), do: ctx

  @spec tuple_elem_types_for_reg(Context.t(), Types.reg()) :: [String.t()]

  defp tuple_elem_types_for_reg(ctx, subject_reg) when is_integer(subject_reg) do
    case type_for_reg(ctx, subject_reg) do
      type when is_binary(type) -> TypeSignature.tuple_element_types(type)
      _ -> []
    end
  end

  @spec type_for_reg(Context.t(), Types.reg()) :: String.t() | nil

  defp type_for_reg(ctx, subject_reg) when is_integer(subject_reg) do
    locals = ctx.locals || %{}
    local_types = ctx.local_types || %{}

    Enum.find_value(locals, fn {name, reg} ->
      if reg == subject_reg, do: Map.get(local_types, name)
    end)
  end

  @spec emit_ctor_payload(Types.pattern(), Types.reg(), Context.t(), Builder.t()) ::
          Types.compile_result()

  defp emit_ctor_payload(pattern, subject_reg, ctx, b) do
    if just_ctor?(pattern) do
      emit_maybe_just_payload(subject_reg, ctx, b)
    else
      emit_union_payload(subject_reg, ctx, b)
    end
  end

  @spec emit_tuple_proj(Types.reg(), atom(), Builder.t()) :: {:ok, Types.reg(), Builder.t()}

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

  @spec emit_union_payload(Types.reg(), Context.t(), Builder.t()) :: Types.compile_result()

  defp emit_union_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:union_payload, [subject_reg], ctx, b)
  end

  @spec emit_maybe_just_payload(Types.reg(), Context.t(), Builder.t()) :: Types.compile_result()

  defp emit_maybe_just_payload(subject_reg, ctx, b) do
    Expr.compile_runtime_builtin(:maybe_just_payload, [subject_reg], ctx, b)
  end

  @spec just_ctor?(Types.pattern()) :: boolean()

  defp just_ctor?(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)
    is_binary(name) and short_name(name) == "Just"
  end

  @spec short_name(String.t()) :: String.t()

  defp short_name(name), do: name |> String.split(".") |> List.last()

  @spec cons_pattern?(map() | term()) :: boolean()

  defp cons_pattern?(%{name: name}) when is_binary(name), do: short_name(name) == "::"
  defp cons_pattern?(%{resolved_name: "List.::"}), do: true
  defp cons_pattern?(_), do: false

  @spec bind_cons_pattern(
          Types.pattern(),
          Types.pattern(),
          Types.reg(),
          Context.t(),
          Builder.t()
        ) :: {:ok, Context.t(), Builder.t()} | :unsupported

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

  @spec nest_tuple_elements([Types.pattern()]) :: [Types.pattern()]

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]

  @spec maybe_enrich_payload_arg_ctx(Context.t(), Types.pattern() | term(), Types.pattern()) ::
          Context.t()

  defp maybe_enrich_payload_arg_ctx(ctx, %{kind: :var, name: name}, pattern)
       when is_binary(name) do
    enrich_constructor_bind_ctx(ctx, name, pattern)
  end

  defp maybe_enrich_payload_arg_ctx(ctx, _arg_pattern, _pattern), do: ctx

  @spec enrich_constructor_bind_ctx(Context.t(), String.t(), Types.pattern()) :: Context.t()

  defp enrich_constructor_bind_ctx(ctx, bind, pattern) when is_binary(bind) do
    case constructor_payload_spec(pattern, ctx) do
      # Result.Ok / Result.Err payload specs are the type variables `value` /
      # `error` from `type Result error value = Ok value | Err error`. Storing
      # those as local types invents a phantom container key
      # `{Module, "value"}` that blocks Model_pageData inline field indices
      # (mainView then reads Ok payload.pageData @ Model@4 → Int(0) →
      # "Page not found").
      spec when is_binary(spec) ->
        if useful_payload_type_spec?(spec) do
          ctx
          |> Context.put_local_type(bind, spec)
          |> maybe_put_inferred_param_fields(bind, spec)
        else
          ctx
        end

      _ ->
        ctx
    end
  end

  @spec useful_payload_type_spec?(String.t()) :: boolean()

  defp useful_payload_type_spec?(spec) when is_binary(spec) do
    trimmed = String.trim(spec)
    trimmed != "" and not TypeSignature.type_variable?(trimmed)
  end

  @spec maybe_put_inferred_param_fields(Context.t(), String.t(), String.t()) :: Context.t()

  defp maybe_put_inferred_param_fields(ctx, bind, spec) when is_binary(bind) and is_binary(spec) do
    if TypeSignature.record_type?(spec) do
      fields =
        spec
        |> TypeSignature.record_field_names()
        |> Enum.map(&to_string/1)
        |> Enum.sort()

      %{ctx | inferred_param_fields: Map.put(ctx.inferred_param_fields, bind, fields)}
    else
      ctx
    end
  end

  @spec constructor_payload_spec(Types.pattern(), Context.t()) :: String.t() | nil

  defp constructor_payload_spec(pattern, ctx) do
    specs = Process.get(:elmc_union_constructor_payload_specs, %{})
    mod = ctx.module

    names =
      [Map.get(pattern, :resolved_name), Map.get(pattern, :name)]
      |> Enum.reject(&is_nil/1)

    keys =
      names
      |> Enum.flat_map(fn name ->
        short = short_name(name)

        home =
          case String.split(to_string(name), ".") do
            parts when length(parts) >= 2 ->
              parts |> Enum.drop(-1) |> Enum.join(".")

            _ ->
              nil
          end

        [
          {mod, name},
          {mod, short},
          if(home, do: {home, short}, else: nil),
          if(home, do: {home, name}, else: nil)
        ]
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.uniq()

    case Enum.find_value(keys, &Map.get(specs, &1)) do
      spec when is_binary(spec) ->
        spec

      _ ->
        # Unique short-name hit across modules (Scene3d.lightPair patterns
        # `Types.Light` while specs are keyed under `Scene3d.Types`).
        names
        |> Enum.map(&short_name/1)
        |> Enum.uniq()
        |> Enum.find_value(fn short ->
          matches =
            for {{_home, ctor}, spec} <- specs,
                is_binary(spec) and (ctor == short or short_name(ctor) == short),
                do: spec

          case Enum.uniq(matches) do
            [only] -> only
            _ -> nil
          end
        end)
    end
  end
end
