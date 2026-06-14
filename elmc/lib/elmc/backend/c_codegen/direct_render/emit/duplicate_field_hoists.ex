defmodule Elmc.Backend.CCodegen.DirectRender.Emit.DuplicateFieldHoists do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.Types

  @spec preamble(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {String.t(), Types.compile_counter()}
  def preamble(expr, env, counter) do
    if Hoist.hoisted_native_ints_enabled?(env) do
    expr
    |> collect_native_field_accesses(env, [])
    |> Enum.group_by(&Hoist.lookup_key/1)
      |> Enum.filter(fn {_key, exprs} -> length(exprs) > 1 end)
      |> Enum.map(fn {_key, [expr | _]} -> expr end)
      |> Enum.reject(&expr_contains_if?/1)
      |> Enum.reduce({"", counter}, fn field_expr, {code_acc, c} ->
        case Host.hoisted_native_int_lookup(env, field_expr) do
          {:ok, _ref} ->
            {code_acc, c}

          :error ->
            {expr_code, ref, c2} = Host.compile_native_int_expr(field_expr, env, c)

            if Hoist.stable_hoist_init?(ref) do
              {hoist_code, _hoisted, c3} =
                Host.maybe_promote_hoisted_native_int(field_expr, env, expr_code, ref, c2)

              {code_acc <> hoist_code, c3}
            else
              {code_acc, c2}
            end
        end
      end)
    else
      {"", counter}
    end
  end

  defp collect_native_field_accesses(expr, env, acc) when is_map(expr) do
    acc =
      if native_field_int_access?(expr, env), do: [expr | acc], else: acc

    Enum.reduce(expr, acc, fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        collect_native_field_accesses(value, env, acc)

      _, acc ->
        acc
    end)
  end

  defp collect_native_field_accesses(expr, env, acc) when is_list(expr),
    do: Enum.reduce(expr, acc, &collect_native_field_accesses(&1, env, &2))

  defp collect_native_field_accesses(_expr, _env, acc), do: acc

  defp native_field_int_access?(%{op: :field_access, arg: arg, field: field} = expr, env)
       when is_binary(field) do
    RecordFields.int_field?(env, arg, field) and
      not RecordFields.union_tag_field?(env, arg, field) and
      Host.native_int_expr?(expr, env)
  end

  defp native_field_int_access?(_expr, _env), do: false

  defp expr_contains_if?(%{op: :if}), do: true

  defp expr_contains_if?(expr) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(&expr_contains_if?/1)
  end

  defp expr_contains_if?(expr) when is_list(expr),
    do: Enum.any?(expr, &expr_contains_if?/1)

  defp expr_contains_if?(_), do: false
end
