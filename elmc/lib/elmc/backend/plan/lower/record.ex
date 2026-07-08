defmodule Elmc.Backend.Plan.Lower.Record do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec compile_update(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile_update(%{base: base, fields: fields}, ctx, b) when is_list(fields) do
  with {:ok, base_reg, b1} <- resolve_base(base, ctx, b),
       {:ok, b2, result_reg} <- apply_field_updates(fields, ctx, b1, base_reg) do
      {:ok, result_reg, b2}
    else
      _ -> :unsupported
    end
  end

  def compile_update(_, _, _), do: :unsupported

  defp resolve_base(%{op: :var, name: name}, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(base, ctx, b) when is_map(base), do: Expr.compile(base, ctx, b)
  defp resolve_base(name, ctx, b) when is_binary(name),
    do: Expr.compile(%{op: :var, name: name}, ctx, b)

  defp resolve_base(_, _, _), do: :unsupported

  defp apply_field_updates([field | rest], ctx, b, current_reg) do
    field_name = Map.get(field, :field) || Map.get(field, :name)
    field_expr = Map.get(field, :expr) || Map.get(field, :value)

    with {:ok, value_reg, b1} <- compile_field_expr(field_expr, ctx, b),
         {:ok, updated_reg, b2} <- cow_drop_update(current_reg, field_name, value_reg, ctx, b1) do
      case rest do
        [] -> {:ok, b2, updated_reg}
        more -> apply_field_updates(more, ctx, b2, updated_reg)
      end
    else
      _ -> :unsupported
    end
  end

  defp apply_field_updates([], _ctx, b, current_reg), do: {:ok, b, current_reg}

  defp cow_drop_update(base_reg, field_name, value_reg, ctx, b) when is_binary(field_name) do
    {value_reg, b0} = Builder.dup_named_local_if_bound(b, value_reg)

    {update_base_reg, b_base} =
      if Builder.borrow_arg?(b0, base_reg) do
        Builder.copy_reg_owned(b0, base_reg)
      else
        {base_reg, b0}
      end

    {dest, b1} = dest_for_update(ctx, b_base)

    {borrows, consumes} = partition_update_args(b1, update_base_reg, value_reg)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, borrows, consumes)
      else
        Types.fallible_transfer(borrows, consumes)
      end

    wrap_catch? = (ctx.fallible or ctx.rc_required) and not Builder.skip_instr_catch?(b1, ctx)

    b2 = if wrap_catch?, do: Builder.catch_begin(b1), else: b1
    field_index = field_index_ref(field_name, ctx)

    {_, b3} =
      Builder.emit(b2, :record_update, %{
        dest: dest,
        args: %{base: update_base_reg, field: field_name, field_index: field_index, value: value_reg},
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
  @spec field_index_for(String.t(), Context.t() | nil) :: String.t()
  def field_index_for(field_name, ctx \\ nil) when is_binary(field_name),
    do: field_index_ref(field_name, ctx)

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

  defp field_index_ref(field_name, ctx) when is_binary(field_name) do
    case field_index_from_shapes(field_name, ctx) do
      idx when is_integer(idx) ->
        Integer.to_string(idx)

      _ ->
        case Process.get(:elmc_record_field_macros, %{}) do
          macros when is_map(macros) ->
            case Enum.find_value(macros, fn {{_mod, _type, name}, macro} ->
                   if name == field_name, do: macro
                 end) do
              macro when is_binary(macro) ->
                case Integer.parse(macro) do
                  {idx, _} -> Integer.to_string(idx)
                  :error -> macro
                end

              _ ->
                "0"
            end

          _ ->
            "0"
        end
    end
  end

  defp field_index_from_shapes(field_name, ctx) when is_binary(field_name) do
    shapes = Process.get(:elmc_record_alias_shapes, %{})

    candidates =
      shapes
      |> Enum.filter(fn {_key, fields} -> field_name in fields end)
      |> Enum.map(fn {key, fields} -> {key, Enum.find_index(fields, &(&1 == field_name))} end)

    case candidates do
      [] ->
        nil

      [{_key, idx}] ->
        idx

      many ->
        module = ctx && Map.get(ctx, :module)

        case module do
          mod when is_binary(mod) ->
            case Enum.find(many, fn {{m, _}, _idx} -> m == mod end) do
              {_key, idx} -> idx
              _ -> elem(hd(many), 1)
            end

          _ ->
            elem(hd(many), 1)
        end
    end
  end

  defp compile_field_expr(expr, ctx, b), do: Expr.compile(expr, ctx, b)

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
