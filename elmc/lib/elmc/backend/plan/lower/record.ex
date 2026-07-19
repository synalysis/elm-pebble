defmodule Elmc.Backend.Plan.Lower.Record do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{Host, RecordFieldMacros, TypeParsing}
  alias Elmc.Backend.CCodegen.Expr, as: CExpr
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Call, Expr}
  alias Elmc.Backend.Plan.Types
  alias ElmEx.IR.TypeSignature

  @spec compile_update(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_update(%{base: base, fields: fields}, ctx, b) when is_list(fields) do
    base_expr = base_expr_for_field(base)

    with {:ok, base_reg, b1} <- resolve_base(base, ctx, b),
         {:ok, b2, result_reg} <- apply_field_updates(fields, ctx, b1, base_reg, base_expr) do
      {:ok, result_reg, b2}
    else
      _ -> :unsupported
    end
  end

  def compile_update(_, _, _), do: :unsupported

  @spec compile_field_call(Types.ir_expr() | String.t(), String.t(), [Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_field_call(arg, field, args, ctx, b) when is_binary(field) do
    args = args || []

    cond do
      args == [] ->
        with {:ok, base, b1} <- resolve_base(arg, ctx, b) do
          compile_record_field_get(base, field, ctx, b1, base_expr_for_field(arg))
        end

      true ->
        with {:ok, base_reg, b1} <- resolve_base(arg, ctx, b),
             {:ok, fn_reg, b2} <-
               compile_record_field_get(base_reg, field, ctx, b1, base_expr_for_field(arg)) do
          Call.compile_closure_call_from_reg(fn_reg, args, ctx, b2)
        end
    end
  end

  defp base_expr_for_field(%{op: :var, name: name}) when is_binary(name),
    do: %{op: :var, name: name}

  defp base_expr_for_field(base) when is_map(base), do: base
  defp base_expr_for_field(name) when is_binary(name), do: %{op: :var, name: name}

  @doc false
  @spec emit_record_field_get(integer(), String.t(), Context.t(), Builder.t(), Types.ir_expr() | nil, keyword()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported
  def emit_record_field_get(base_reg, field, ctx, b, base_expr \\ nil, opts \\ [])

      when is_integer(base_reg) and is_binary(field) do
    compile_record_field_get(base_reg, field, ctx, b, base_expr, opts)
  end

  defp compile_record_field_get(base_reg, field, ctx, b, base_expr),
    do: compile_record_field_get(base_reg, field, ctx, b, base_expr, [])

  defp compile_record_field_get(base_reg, field, ctx, b, base_expr, opts) when is_integer(base_reg) do
    {reg, b1} = Builder.fresh_reg(b)

    field_index =
      case Keyword.get(opts, :index_override) do
        idx when is_integer(idx) and idx >= 0 ->
          RecordFieldMacros.format_index(idx, field, nil)

        _ ->
          field_index_ref(field, ctx, base_expr)
      end

    int_field? = int_field?(field)

    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base_reg, field: field, field_index: field_index},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [base_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  defp resolve_base(%{op: :var, name: name}, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(base, ctx, b) when is_map(base), do: Expr.compile(base, ctx, b)
  defp resolve_base(name, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(_, _, _), do: :unsupported

  defp apply_field_updates([field | rest], ctx, b, current_reg, base_expr) do
    field_name = Map.get(field, :field) || Map.get(field, :name)
    field_expr = Map.get(field, :expr) || Map.get(field, :value)

    with {:ok, value_reg, b1} <- compile_field_expr(field_expr, ctx, b),
         {:ok, updated_reg, b2} <-
           cow_drop_update(current_reg, field_name, value_reg, ctx, b1, base_expr) do
      case rest do
        [] -> {:ok, b2, updated_reg}
        more -> apply_field_updates(more, ctx, b2, updated_reg, base_expr)
      end
    else
      _ -> :unsupported
    end
  end

  defp apply_field_updates([], _ctx, b, current_reg, _base_expr), do: {:ok, b, current_reg}

  defp cow_drop_update(base_reg, field_name, value_reg, ctx, b, base_expr)
       when is_binary(field_name) do
    {value_reg, b0} = Builder.dup_named_local_if_bound(b, value_reg)

    {update_base_reg, b_base, retain_copy?} =
      if Builder.borrow_arg?(b0, base_reg) do
        {dup, b_copy} = Builder.copy_reg_owned(b0, base_reg)
        {dup, b_copy, true}
      else
        {base_reg, b0, false}
      end

    {dest, b1} = dest_for_update(ctx, b_base)

    {borrows, consumes} = partition_update_args(b1, update_base_reg, value_reg)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        Types.fallible_transfer(borrows, consumes)
      end

    wrap_catch? = Builder.wrap_fallible_instr_catch?(b1, ctx, true)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1
    field_index = field_index_ref(field_name, ctx, base_expr)

    {_, b3} =
      Builder.emit(b2, :record_update, %{
        dest: dest,
        args: %{
          base: update_base_reg,
          field: field_name,
          field_index: field_index,
          value: value_reg,
          retain_copy: retain_copy?
        },
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3

    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  @doc false
  @spec canonicalize_literal_fields([Types.ir_record_field()], Context.t()) :: [Types.ir_record_field()]
  def canonicalize_literal_fields(fields, ctx) when is_list(fields) do
    names = Enum.map(fields, &field_name/1)

    case canonical_shape_for_names(names, ctx.module) do
      nil ->
        fields

      canonical_names ->
        ordered =
          Enum.map(canonical_names, fn name ->
            Enum.find(fields, &(field_name(&1) == name))
          end)

        if Enum.all?(ordered, & &1), do: ordered, else: fields
    end
  end

  @doc false
  @spec int_field?(String.t()) :: boolean()
  def int_field?(field_name) when is_binary(field_name) do
    Process.get(:elmc_record_field_types, %{})
    |> Map.values()
    |> Enum.any?(fn fields when is_map(fields) ->
      Map.get(fields, field_name) == "Int" or Map.get(fields, to_string(field_name)) == "Int"
    end)
  end

  @doc false
  @spec field_index_for(String.t(), Context.t() | nil, Types.ir_expr() | nil) :: String.t()
  def field_index_for(field_name, ctx \\ nil, base_expr \\ nil) when is_binary(field_name),
    do: field_index_ref(field_name, ctx, base_expr)

  @doc false
  @spec resolve_field_index_int(String.t(), Context.t() | nil, Types.ir_expr() | nil) ::
          {:ok, integer()} | :error
  def resolve_field_index_int(field_name, ctx \\ nil, base_expr \\ nil)
      when is_binary(field_name) do
    case field_index_from_callee_record_literal(field_name, ctx, base_expr) do
      idx when is_integer(idx) ->
        {:ok, idx}

      _ ->
        case field_index_from_binding_decl_type(field_name, ctx, base_expr) do
          idx when is_integer(idx) ->
            {:ok, idx}

          _ ->
            case resolve_field_type_key(field_name, ctx, base_expr) do
              {_key, idx} when is_integer(idx) -> {:ok, idx}
              _ -> :error
            end
        end
    end
  end

  defp field_name(field), do: Map.get(field, :name) || Map.get(field, :field)

  # Top-level values like `Shared.template = { init, update, view, … }` are record
  # literals in IR. When lowering `Shared.template.view`, the base expression is the
  # zero-arg call — resolve field indices from that literal's declaration order.
  defp field_index_from_callee_record_literal(field_name, ctx, base_expr)
       when is_binary(field_name) do
    case callee_decl_for_base_expr(base_expr, ctx) do
      %{expr: %{op: :record_literal, fields: fields}} when is_list(fields) ->
        Enum.find_index(fields, &(field_name(&1) == field_name))

      _ ->
        nil
    end
  end

  defp callee_decl_for_base_expr(%{op: :field_access, arg: inner}, ctx) when is_map(inner) do
    callee_decl_for_base_expr(inner, ctx)
  end

  defp callee_decl_for_base_expr(%{op: :qualified_call, target: target, args: args}, ctx)
       when is_binary(target) and is_list(args) do
    if args == [] do
      callee_decl_for_qualified_target(target, ctx)
    end
  end

  defp callee_decl_for_base_expr(%{op: :qualified_ref, target: target}, ctx)
       when is_binary(target) do
    callee_decl_for_qualified_target(target, ctx)
  end

  defp callee_decl_for_base_expr(%{op: :call, name: name, args: args}, ctx)
       when is_binary(name) and is_list(args) do
    if args == [] and is_binary(ctx && ctx.module) do
      Map.get(ctx.decl_map || %{}, {ctx.module, name})
    end
  end

  defp callee_decl_for_base_expr(_, _), do: nil

  # Top-level bindings like `Route.Index.route : StatelessRoute …` are not record
  # literals in IR, but field access must use the alias record shape (StatefulRoute),
  # not unrelated inline shapes that happen to mention the same field name.
  defp field_index_from_binding_decl_type(field_name, ctx, base_expr) when is_binary(field_name) do
    case callee_decl_for_base_expr(base_expr, ctx) do
      %{type: type} when is_binary(type) ->
        case record_shape_key_from_decl_type(type, ctx) do
          key when is_tuple(key) ->
            case Map.get(Process.get(:elmc_record_alias_shapes, %{}), key) do
              fields when is_list(fields) ->
                Enum.find_index(fields, &(&1 == field_name))

              _ ->
                nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp record_shape_key_from_decl_type(type, ctx) when is_binary(type) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})
    ctor = type |> Host.normalize_type_name() |> type_constructor_name()

    case CExpr.split_qualified_type_name(ctor) do
      {mod, name} ->
        key = {mod, name}
        record_shape_key_or_synonym(key, shapes)

      _ ->
        case shape_key_by_name(shapes, ctor, ctx) do
          key when is_tuple(key) -> record_shape_key_or_synonym(key, shapes)
          _ -> record_shape_key_or_synonym({nil, ctor}, shapes)
        end
    end
  end

  defp record_shape_key_or_synonym({mod, name}, shapes) when is_binary(name) do
    key = if is_binary(mod), do: {mod, name}, else: shape_key_by_name(shapes, name, %{module: mod})

    cond do
      is_tuple(key) and Map.has_key?(shapes, key) ->
        key

      is_binary(mod) and name == "StatelessRoute" and Map.has_key?(shapes, {mod, "StatefulRoute"}) ->
        {mod, "StatefulRoute"}

      name == "StatelessRoute" ->
        shape_key_by_record_name(shapes, "StatefulRoute")

      true ->
        nil
    end
  end

  defp shape_key_by_record_name(shapes, record_name) when is_binary(record_name) and is_map(shapes) do
    case Enum.filter(shapes, fn {{_mod, name}, _fields} -> name == record_name end) do
      [{key, _}] -> key
      many when length(many) > 1 -> elem(hd(many), 0)
      _ -> nil
    end
  end

  defp callee_decl_for_qualified_target(target, ctx) when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {module, name} when is_binary(module) and is_binary(name) ->
        decl_map = (ctx && ctx.decl_map) || %{}
        Map.get(decl_map, {module, name})

      _ ->
        nil
    end
  end

  defp canonical_shape_for_names(field_names, module) when is_list(field_names) do
    normalized = field_names |> Enum.map(&to_string/1) |> Enum.sort()

    matches =
      Process.get(:elmc_record_alias_shapes, %{})
      |> Enum.filter(fn {{_mod, _name}, shape} ->
        Enum.sort(Enum.map(shape, &to_string/1)) == normalized
      end)

    matches =
      if matches == [] do
        Process.get(:elmc_inline_record_literal_shapes, %{})
        |> Enum.filter(fn {{_mod, _name}, shape} ->
          Enum.sort(Enum.map(shape, &to_string/1)) == normalized
        end)
      else
        matches
      end

    case matches do
      [] ->
        nil

      many ->
        case module do
          mod when is_binary(mod) ->
            case Enum.find(many, fn {{m, _}, _} -> m == mod end) do
              {{_, _}, shape} -> shape
              _ -> elem(hd(many), 1)
            end

          _ ->
            elem(hd(many), 1)
        end
    end
  end

  defp field_index_ref(field_name, ctx, base_expr) when is_binary(field_name) do
    case field_index_from_callee_record_literal(field_name, ctx, base_expr) do
      idx when is_integer(idx) ->
        RecordFieldMacros.format_index(idx, field_name, nil)

      _ ->
        case field_index_from_binding_decl_type(field_name, ctx, base_expr) do
          idx when is_integer(idx) ->
            RecordFieldMacros.format_index(idx, field_name, nil)

          _ ->
            case param_or_typed_var_field_index(field_name, ctx, base_expr) do
              {key, idx} when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, key)

              _ ->
                field_index_ref_from_type(field_name, ctx, base_expr)
            end
        end
    end
  end

  defp param_or_typed_var_field_index(field_name, ctx, base_expr) when is_binary(field_name) do
    if param_var_base?(base_expr, ctx) do
      inline_result = inline_field_index_from_base(field_name, ctx, base_expr)
      alias_result = alias_field_index_for_param(field_name, ctx, base_expr)

      case reconcile_param_field_indices(inline_result, alias_result, field_name, ctx, base_expr) do
        {:inline, idx} when is_integer(idx) ->
          {nil, idx}

        {key, idx} when is_integer(idx) ->
          {key, idx}

        :error ->
          nil
      end
    else
      nil
    end
  end

  defp reconcile_param_field_indices(inline, alias_result, field_name, ctx, base_expr) do
    case {inline, alias_result} do
      {:error, :error} ->
        :error

      {:error, {key, idx}} ->
        {key, idx}

      {{:inline, inferred_idx}, {key, alias_idx}} when inferred_idx != alias_idx ->
        if prefer_alias_field_index?(field_name, ctx, base_expr, key, alias_idx),
          do: {key, alias_idx},
          else: {:inline, inferred_idx}

      {{key, inferred_idx}, {_, alias_idx}} when inferred_idx != alias_idx ->
        if prefer_alias_field_index?(field_name, ctx, base_expr, key, alias_idx),
          do: alias_result,
          else: inline

      {result, _} when result != :error ->
        result

      {_, alias} ->
        alias
    end
  end

  defp prefer_alias_field_index?(field_name, ctx, %{op: :var, name: param}, key, _alias_idx)
       when is_binary(field_name) and is_binary(param) do
    inferred_fields = Map.get((ctx && ctx.inferred_param_fields) || %{}, param, [])
    alias_fields = Map.get(Process.get(:elmc_record_alias_shapes, %{}), key, [])

    cond do
      inferred_fields == [] ->
        false

      not is_list(alias_fields) or alias_fields == [] ->
        false

      inferred_fields == alias_fields ->
        false

      normalize_field_names(inferred_fields) != normalize_field_names(alias_fields) ->
        false

      Enum.find_index(inferred_fields, &(&1 == field_name)) !=
          Enum.find_index(alias_fields, &(&1 == field_name)) ->
        true

      true ->
        false
    end
  end

  defp prefer_alias_field_index?(_, _, _, _, _), do: false

  defp alias_field_index_for_param(field_name, ctx, %{op: :var, name: param_name})
       when is_binary(field_name) and is_binary(param_name) do
    env = compile_env(ctx)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    type =
      env
      |> Map.get(:__var_types__, %{})
      |> Map.get(param_name)

    cond do
      is_binary(type) and extensible_record_type?(type) ->
        case max_field_index_among_shapes(field_name, shapes) do
          {key, idx} when is_integer(idx) -> {key, idx}
          _ -> :error
        end

      is_binary(type) ->
        case record_key_from_type(type, ctx) do
          key when is_tuple(key) ->
            case Map.get(shapes, key) do
              fields when is_list(fields) ->
                case Enum.find_index(fields, &(&1 == field_name)) do
                  idx when is_integer(idx) -> {key, idx}
                  _ -> min_alias_field_index(field_name, shapes)
                end

              _ ->
                min_alias_field_index(field_name, shapes)
            end

          _ ->
            min_alias_field_index(field_name, shapes)
        end

      true ->
        case shape_key_for_inferred_fields(Map.get((ctx && ctx.inferred_param_fields) || %{}, param_name), ctx) do
          key when is_tuple(key) ->
            case Map.get(shapes, key) do
              fields when is_list(fields) ->
                case Enum.find_index(fields, &(&1 == field_name)) do
                  idx when is_integer(idx) -> {key, idx}
                  _ -> min_alias_field_index(field_name, shapes)
                end

              _ ->
                min_alias_field_index(field_name, shapes)
            end

          _ ->
            min_alias_field_index(field_name, shapes)
        end
    end
  end

  defp alias_field_index_for_param(_, _, _), do: :error

  defp min_alias_field_index(field_name, shapes) when is_binary(field_name) do
    case min_field_index_among_shapes(field_name, shapes) do
      {key, idx} when is_integer(idx) -> {key, idx}
      _ -> :error
    end
  end

  defp field_index_ref_from_type(field_name, ctx, base_expr) when is_binary(field_name) do
    case resolve_field_type_key(field_name, ctx, base_expr) do
      {:inline, idx} ->
        RecordFieldMacros.format_index(idx, field_name, nil)

      {{mod, type}, idx} when is_integer(idx) ->
        RecordFieldMacros.format_index(idx, field_name, {mod, type})

      _ ->
        shapes = Process.get(:elmc_record_alias_shapes, %{})
        env = compile_env(ctx)

        container_type =
          case base_expr do
            expr when is_map(expr) -> CExpr.record_container_type_for_expr(expr, env)
            _ -> nil
          end

        cond do
          is_binary(container_type) and extensible_record_type?(container_type) ->
            case max_field_index_among_shapes(field_name, shapes) do
              {key, idx} when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, key)

              _ ->
                field_index_macro_fallback(field_name, ctx, base_expr)
            end

          true ->
            case ambiguous_field_type_key(field_name, ctx, shapes, base_expr) do
              {key, idx} when is_integer(idx) ->
                RecordFieldMacros.format_index(idx, field_name, key)

              _ ->
                case ambiguous_field_candidates(field_name, shapes) do
                  [] ->
                    field_index_macro_fallback(field_name, ctx, base_expr)

                  [{key, idx}] ->
                    RecordFieldMacros.format_index(idx, field_name, key)

                  many ->
                    case pick_ambiguous_field_type_key(many, ctx, base_expr) do
                      {key, idx} when is_integer(idx) ->
                        RecordFieldMacros.format_index(idx, field_name, key)

                      _ ->
                        field_index_macro_fallback(field_name, ctx, base_expr)
                    end
                end
            end
        end
    end
  end

  defp field_index_macro_fallback(field_name, ctx \\ nil, base_expr \\ nil)
       when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case ambiguous_field_candidates(field_name, shapes) do
      [] ->
        numeric_field_index_fallback(field_name)

      [{_key, idx}] ->
        "#{idx} /* #{field_name} */"

      many ->
        case pick_ambiguous_field_type_key(many, ctx, base_expr) do
          {key, idx} when is_integer(idx) ->
            RecordFieldMacros.format_index(idx, field_name, key)

          _ ->
            numeric_field_index_fallback(field_name)
        end
    end
  end

  defp numeric_field_index_fallback(field_name) when is_binary(field_name) do
    case Process.get(:elmc_record_field_macros, %{}) do
      macros when is_map(macros) ->
        case Enum.find_value(macros, fn {{_mod, _type, name}, macro} ->
               if name == field_name, do: macro
             end) do
          macro when is_binary(macro) -> macro
          _ -> "0"
        end

      _ ->
        "0"
    end
  end

  defp resolve_field_type_key(field_name, ctx, base_expr) when is_binary(field_name) do
    env = compile_env(ctx)

    container_type =
      case base_expr do
        expr when is_map(expr) -> CExpr.record_container_type_for_expr(expr, env)
        _ -> nil
      end

    if is_binary(container_type) and extensible_record_type?(container_type) do
      case max_field_index_among_shapes(field_name, Process.get(:elmc_record_alias_shapes, %{})) do
        {key, idx} when is_integer(idx) -> {key, idx}
        _ -> resolve_field_type_key_concrete(field_name, ctx, base_expr)
      end
    else
      resolve_field_type_key_concrete(field_name, ctx, base_expr)
    end
  end

  defp resolve_field_type_key_concrete(field_name, ctx, base_expr) when is_binary(field_name) do
    case inline_field_index_from_base(field_name, ctx, base_expr) do
      {:inline, idx} ->
        {:inline, idx}

      {{_mod, _type} = key, idx} when is_integer(idx) ->
        {key, idx}

      :error ->
        case inline_field_index_from_container_type(field_name, ctx, base_expr) do
          {:inline, idx} -> {:inline, idx}
          :error -> resolve_field_type_key_from_shapes(field_name, ctx, base_expr)
        end
    end
  end

  defp inline_field_index_from_container_type(field_name, ctx, base_expr)
       when is_binary(field_name) do
    env = compile_env(ctx)

    with type when is_binary(type) <- CExpr.record_container_type_for_expr(base_expr, env),
         false <- extensible_record_type?(type),
         true <- TypeSignature.record_type?(type),
         declared_fields when is_list(declared_fields) and declared_fields != [] <-
           TypeSignature.record_field_names(type),
         idx when is_integer(idx) <- inline_literal_shapes_field_index(field_name, declared_fields) do
      {:inline, idx}
    else
      _ ->
        with type when is_binary(type) <- CExpr.record_container_type_for_expr(base_expr, env),
             false <- extensible_record_type?(type),
             true <- TypeSignature.record_type?(type),
             fields when is_list(fields) and fields != [] <- elm_inline_record_field_names(type),
             idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
          {:inline, idx}
        else
          _ -> :error
        end
    end
  end

  defp extensible_record_type?(type) when is_binary(type), do: String.contains?(type, "|")

  # Elm stores record fields in alphabetical order at runtime.
  defp elm_inline_record_field_names(type) when is_binary(type) do
    type |> TypeSignature.record_field_names() |> Enum.sort()
  end

  defp inline_literal_shapes_field_index(field_name, declared_fields)
       when is_binary(field_name) and is_list(declared_fields) do
    normalized = declared_fields |> Enum.map(&to_string/1) |> Enum.sort()

    shapes =
      Process.get(:elmc_inline_record_literal_shapes, %{})
      |> Map.merge(Process.get(:elmc_record_alias_shapes, %{}))

    case Enum.find_value(shapes, fn {_key, shape} ->
           shape_names = shape |> Enum.map(&to_string/1)

           if Enum.sort(shape_names) == normalized do
             shape_names
           end
         end) do
      shape when is_list(shape) -> Enum.find_index(shape, &(&1 == field_name))
      _ -> nil
    end
  end

  defp inline_field_index_from_base(field_name, ctx, %{op: :var, name: name})
       when is_binary(field_name) and is_binary(name) do
    env = compile_env(ctx)

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         key when is_tuple(key) <- record_key_from_type(type, ctx),
         fields when is_list(fields) <-
           Map.get(Process.get(:elmc_record_alias_shapes, %{}), key),
         idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
      {key, idx}
    else
      _ ->
        inline_field_index_from_concrete_var(field_name, ctx, name)
    end
  end

  defp inline_field_index_from_base(_field_name, _ctx, _base_expr), do: :error

  defp inline_field_index_from_concrete_var(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    case inline_field_index_from_declared_param_type(field_name, ctx, name) do
      {:inline, _} = ok ->
        ok

      {_, _} = ok ->
        ok

      :error ->
        inline_field_index_from_inferred_param(field_name, ctx, name)
    end
  end

  defp inline_field_index_from_declared_param_type(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    env = compile_env(ctx)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
         key when is_tuple(key) <- record_key_from_type(type, ctx),
         fields when is_list(fields) <- Map.get(shapes, key),
         idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
      {key, idx}
    else
      _ ->
        with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
             false <- extensible_record_type?(type),
             declared_fields when is_list(declared_fields) and declared_fields != [] <-
               TypeSignature.record_field_names(type),
             idx when is_integer(idx) <-
               inline_literal_shapes_field_index(field_name, declared_fields) do
          {:inline, idx}
        else
          _ ->
            with type when is_binary(type) <- Map.get(env, :__var_types__, %{}) |> Map.get(name),
                 false <- extensible_record_type?(type),
                 fields when is_list(fields) and fields != [] <- elm_inline_record_field_names(type),
                 idx when is_integer(idx) <- Enum.find_index(fields, &(&1 == field_name)) do
              {:inline, idx}
            else
              _ -> :error
            end
        end
    end
  end

  defp inline_field_index_from_inferred_param(field_name, ctx, name)
       when is_binary(field_name) and is_binary(name) do
    fields =
      case ctx do
        %{inferred_param_fields: inferred} when is_map(inferred) -> Map.get(inferred, name)
        _ -> nil
      end

    case fields do
      list when is_list(list) and list != [] ->
        case shape_key_for_inferred_fields(list, ctx) do
          key when is_tuple(key) ->
            case Map.get(Process.get(:elmc_record_alias_shapes, %{}), key) do
              shape when is_list(shape) ->
                case Enum.find_index(shape, &(&1 == field_name)) do
                  idx when is_integer(idx) -> {key, idx}
                  _ -> :error
                end

              _ ->
                :error
            end

          _ ->
            case Enum.find_index(list, &(&1 == field_name)) do
              idx when is_integer(idx) -> {:inline, idx}
              _ -> :error
            end
        end

      _ ->
        :error
    end
  end

  defp shape_key_for_inferred_fields(inferred_fields, ctx) when is_list(inferred_fields) do
    inferred_set = MapSet.new(inferred_fields, &to_string/1)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    candidates =
      shapes
      |> Enum.filter(fn {_key, shape} ->
        MapSet.subset?(inferred_set, MapSet.new(shape, &to_string/1))
      end)

    case candidates do
      [] ->
        nil

      [{key, _}] ->
        key

      many ->
        module = ctx && Map.get(ctx, :module)

        case module do
          mod when is_binary(mod) ->
            case Enum.find(many, fn {{m, _}, _} -> m == mod end) do
              {key, _} -> key
              _ -> pick_most_specific_shape_candidate(many, inferred_set)
            end

          _ ->
            pick_most_specific_shape_candidate(many, inferred_set)
        end
    end
  end

  defp shape_key_for_inferred_fields(_, _), do: nil

  defp pick_most_specific_shape_candidate(candidates, inferred_set) when is_list(candidates) do
    exact =
      Enum.filter(candidates, fn {_key, shape} ->
        MapSet.equal?(inferred_set, MapSet.new(shape, &to_string/1))
      end)

    case exact do
      [{key, _} | _] ->
        key

      _ ->
        candidates
        |> Enum.min_by(fn {_key, shape} -> length(shape) end)
        |> elem(0)
    end
  end

  defp normalize_field_names(fields) when is_list(fields) do
    fields |> Enum.map(&to_string/1) |> Enum.sort()
  end

  defp resolve_field_type_key_from_shapes(field_name, ctx, base_expr) when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case container_record_key(base_expr, ctx) do
      key when is_tuple(key) ->
        case Map.get(shapes, key) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
            end

          _ ->
            ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
        end

      _ ->
        ambiguous_field_type_key(field_name, ctx, shapes, base_expr)
    end
  end

  defp ambiguous_field_type_key(field_name, ctx, shapes, base_expr) do
    case prefer_inline_shape_field_index(field_name, shapes, ctx, base_expr) do
      {key, idx} when is_integer(idx) ->
        {key, idx}

      _ ->
        ambiguous_field_type_key_from_alias(field_name, ctx, shapes, base_expr)
    end
  end

  defp prefer_inline_shape_field_index(field_name, shapes, ctx, base_expr)
       when is_binary(field_name) do
    inline_shapes = Process.get(:elmc_inline_record_literal_shapes, %{})

    case container_record_key(base_expr, ctx) do
      key when is_tuple(key) ->
        case Map.get(inline_shapes, key) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        if param_var_base?(base_expr, ctx) do
          case inline_field_index_from_base(field_name, ctx, base_expr) do
            {:inline, idx} when is_integer(idx) ->
              {nil, idx}

            {key, idx} when is_integer(idx) ->
              {key, idx}

            :error ->
              prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
          end
        else
          prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
        end
    end
  end

  defp param_var_base?(%{op: :var, name: name}, ctx) when is_binary(name) do
    params = (ctx && Map.get(ctx, :params)) || []
    name in params
  end

  defp param_var_base?(_, _), do: false

  defp prefer_inline_shape_when_container_unknown(field_name, shapes, inline_shapes)
       when is_binary(field_name) and is_map(shapes) and is_map(inline_shapes) do
    inline_candidates =
      inline_shapes
      |> Enum.filter(fn {_, fields} -> field_name in fields end)
      |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)
      |> Enum.filter(fn {_, idx} -> is_integer(idx) end)

    case inline_candidates do
      [] ->
        nil

      candidates ->
        {key, idx} = Enum.min_by(candidates, fn {_, i} -> i end)

        alias_candidates =
          shapes
          |> Enum.filter(fn {_, fields} -> field_name in fields end)
          |> Enum.map(fn {k, fields} -> {k, Enum.find_index(fields, &(&1 == field_name))} end)
          |> Enum.filter(fn {_, i} -> is_integer(i) end)

        case alias_candidates do
          [] ->
            {key, idx}

          alias_many ->
            {_, alias_idx} = Enum.max_by(alias_many, fn {_, i} -> i end)
            if idx < alias_idx, do: {key, idx}, else: nil
        end
    end
  end

  defp ambiguous_field_type_key_from_alias(field_name, ctx, shapes, base_expr) do
    candidates =
      shapes
      |> Enum.filter(fn {_key, fields} -> field_name in fields end)
      |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)

    case candidates do
      [] ->
        nil

      [{key, idx}] ->
        {key, idx}

      many ->
        case container_record_key(base_expr, ctx) do
          key when is_tuple(key) ->
            case Enum.find(many, fn {candidate, _idx} -> candidate == key end) do
              {key, idx} -> {key, idx}
              _ -> pick_ambiguous_field_type_key(many, ctx, base_expr)
            end

          _ ->
            pick_ambiguous_field_type_key(many, ctx, base_expr)
        end
    end
  end

  defp pick_ambiguous_field_type_key(many, ctx, _base_expr) when is_list(many) do
    module = ctx && Map.get(ctx, :module)

    case module do
      mod when is_binary(mod) ->
        case Enum.find(many, fn {{m, _}, _idx} -> m == mod end) do
          {key, idx} -> {key, idx}
          _ -> hd(many)
        end

      _ ->
        hd(many)
    end
  end

  defp max_field_index_among_shapes(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
    |> case do
      [] -> nil
      candidates -> Enum.max_by(candidates, fn {_key, idx} -> idx end)
    end
  end

  defp min_field_index_among_shapes(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
    |> case do
      [] -> nil
      candidates -> Enum.min_by(candidates, fn {_key, idx} -> idx end)
    end
  end

  defp ambiguous_field_candidates(field_name, shapes) when is_binary(field_name) do
    shape_field_index_candidates(field_name, shapes)
  end

  defp shape_field_index_candidates(field_name, shapes) when is_binary(field_name) do
    shapes
    |> Enum.filter(fn {_key, fields} -> field_name in fields end)
    |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)
    |> Enum.filter(fn {_key, idx} -> is_integer(idx) end)
  end

  defp container_record_key(base_expr, ctx) do
    env = compile_env(ctx)

    case CExpr.record_container_type_for_expr(base_expr, env) do
      type when is_binary(type) ->
        record_key_from_type(type, ctx)

      _ ->
        nil
    end
  end

  defp record_key_from_type(type, ctx) do
    normalized = Host.normalize_type_name(type)
    type_name = type_constructor_name(normalized)
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case CExpr.split_qualified_type_name(type_name) do
      {mod, name} ->
        if Map.has_key?(shapes, {mod, name}), do: {mod, name}, else: shape_key_by_name(shapes, name, ctx)

      _ ->
        shape_key_by_name(shapes, type_name, ctx)
    end
  end

  defp type_constructor_name(type) when is_binary(type) do
    case String.split(type, ~r/\s+/, parts: 2) do
      [base, _rest] -> base
      [base] -> base
    end
  end

  defp shape_key_by_name(shapes, name, ctx) when is_binary(name) do
    module = ctx && Map.get(ctx, :module)

    matches =
      shapes
      |> Enum.filter(fn {{_mod, record}, _fields} -> record == name end)

    case matches do
      [{key, _}] ->
        key

      many when length(many) > 1 and is_binary(module) ->
        case Enum.find(many, fn {{mod, _}, _} -> mod == module end) do
          {key, _} -> key
          _ -> elem(hd(many), 0)
        end

      [{key, _} | _] ->
        key

      _ ->
        if is_binary(module), do: {module, name}, else: nil
    end
  end

  defp compile_env(ctx) do
    var_types =
      ctx
      |> param_var_types()
      |> Map.merge(local_param_types(ctx))

    %{
      __module__: (ctx && ctx.module) || "Main",
      __var_types__: var_types,
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  defp local_param_types(%Context{local_types: types}) when is_map(types), do: types
  defp local_param_types(_), do: %{}

  defp param_var_types(ctx) do
    with %Context{decl_map: decl_map, module: module, params: params, function_name: fun} <- ctx,
         fun when is_binary(fun) <- fun,
         decl when is_map(decl) <- Map.get(decl_map || %{}, {module, fun}, %{}),
         type when is_binary(type) <- Map.get(decl, :type),
         arg_types when is_list(arg_types) <- TypeParsing.function_arg_types(type) do
      params
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {name, idx}, acc ->
        case Enum.at(arg_types, idx) do
          arg_type when is_binary(arg_type) -> Map.put(acc, name, arg_type)
          _ -> acc
        end
      end)
    else
      _ -> %{}
    end
  end

  defp compile_field_expr(expr, ctx, b) do
    Expr.compile(expr, Context.for_branch_arm(ctx), b)
  end

  defp dest_for_update(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end

  defp partition_update_args(b, base_reg, value_reg) do
    base_effects =
      if Builder.borrow_arg?(b, base_reg), do: {[base_reg], []}, else: {[], [base_reg]}

    {base_borrows, _base_consumes} = base_effects
    {base_borrows, [value_reg]}
  end
end
