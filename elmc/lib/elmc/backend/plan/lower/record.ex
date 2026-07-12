defmodule Elmc.Backend.Plan.Lower.Record do
  @moduledoc false

  alias Elmc.Backend.CCodegen.{Host, RecordFieldMacros, TypeParsing}
  alias Elmc.Backend.CCodegen.Expr, as: CExpr
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Call, Expr}
  alias Elmc.Backend.Plan.Types

  @spec compile_update(map(), Context.t(), Builder.t()) ::
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

  @spec compile_field_call(map() | String.t(), String.t(), [map()], Context.t(), Builder.t()) ::
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

  defp compile_record_field_get(base_reg, field, ctx, b, base_expr)
       when is_integer(base_reg) do
    {reg, b1} = Builder.fresh_reg(b)
    field_index = field_index_ref(field, ctx, base_expr)
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
  @spec canonicalize_literal_fields([map()], Context.t()) :: [map()]
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
  @spec field_index_for(String.t(), Context.t() | nil, term()) :: String.t()
  def field_index_for(field_name, ctx \\ nil, base_expr \\ nil) when is_binary(field_name),
    do: field_index_ref(field_name, ctx, base_expr)

  @doc false
  @spec resolve_field_index_int(String.t(), Context.t() | nil, term()) ::
          {:ok, integer()} | :error
  def resolve_field_index_int(field_name, ctx \\ nil, base_expr \\ nil)
      when is_binary(field_name) do
    case resolve_field_type_key(field_name, ctx, base_expr) do
      {_key, idx} when is_integer(idx) -> {:ok, idx}
      _ -> :error
    end
  end

  defp field_name(field), do: Map.get(field, :name) || Map.get(field, :field)

  defp canonical_shape_for_names(field_names, module) when is_list(field_names) do
    normalized = field_names |> Enum.map(&to_string/1) |> Enum.sort()

    matches =
      Process.get(:elmc_record_alias_shapes, %{})
      |> Enum.filter(fn {{_mod, _name}, shape} ->
        Enum.sort(Enum.map(shape, &to_string/1)) == normalized
      end)

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

  defp field_index_ref(field_name, ctx, base_expr \\ nil) when is_binary(field_name) do
    case resolve_field_type_key(field_name, ctx, base_expr) do
      {{mod, type}, idx} when is_integer(idx) ->
        RecordFieldMacros.format_index(idx, field_name, {mod, type})

      _ ->
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
  end

  defp resolve_field_type_key(field_name, ctx, base_expr) when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case container_record_key(base_expr, ctx) do
      key when is_tuple(key) ->
        case Map.get(shapes, key) do
          fields when is_list(fields) ->
            case Enum.find_index(fields, &(&1 == field_name)) do
              idx when is_integer(idx) -> {key, idx}
              _ -> ambiguous_field_type_key(field_name, ctx, shapes)
            end

          _ ->
            ambiguous_field_type_key(field_name, ctx, shapes)
        end

      _ ->
        ambiguous_field_type_key(field_name, ctx, shapes)
    end
  end

  defp ambiguous_field_type_key(field_name, ctx, shapes) do
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
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    case CExpr.split_qualified_type_name(normalized) do
      {mod, name} ->
        if Map.has_key?(shapes, {mod, name}), do: {mod, name}, else: shape_key_by_name(shapes, name, ctx)

      _ ->
        shape_key_by_name(shapes, normalized, ctx)
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
    %{
      __module__: (ctx && ctx.module) || "Main",
      __var_types__: param_var_types(ctx),
      __record_field_types__: Process.get(:elmc_record_field_types, %{}),
      __record_field_kinds__: Process.get(:elmc_record_field_kinds, %{})
    }
  end

  defp param_var_types(ctx) do
    with %Context{decl_map: decl_map, module: module, params: params} <- ctx,
         decl when is_map(decl) <- Map.get(decl_map, {module, ctx.function_name}, %{}),
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
