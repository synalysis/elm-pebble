defmodule Elmc.Backend.CCodegen.DirectRender.Emit.DuplicateFieldHoists do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
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
      |> Enum.reduce({"", counter}, fn field_expr, {code_acc, c} ->
        case Host.hoisted_native_int_lookup(env, field_expr) do
          {:ok, _ref} ->
            {code_acc, c}

          :error ->
            {expr_code, ref, c2} = Host.compile_native_int_expr(field_expr, env, c)

            if Hoist.stable_hoist_init?(ref) or record_get_hoist_init?(expr_code) do
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

  defp record_get_hoist_init?(init) when is_binary(init),
    do: String.starts_with?(init, "ELMC_RECORD_GET_INDEX_INT(")

  defp record_get_hoist_init?(_), do: false

  defp canonical_field_access(%{op: :field_access, arg: arg, field: field} = expr, env) do
    %{expr | arg: canonical_field_arg(arg, env), field: field}
  end

  defp canonical_field_access(expr, _env), do: expr

  defp canonical_field_arg(%{op: :var, name: name}, env) do
    key = EnvBindings.binding_key(name)

    case EnvBindings.lookup_binding(env, key) do
      c_ref when is_binary(c_ref) ->
        if EnvBindings.direct_param_ref?(env, c_ref) do
          %{op: :var, name: c_ref}
        else
          %{op: :var, name: name}
        end

      _ ->
        case EnvBindings.let_value_expr(env, name) do
          inner when is_map(inner) -> canonical_field_arg(inner, env)
          _ -> %{op: :var, name: name}
        end
    end
  end

  defp canonical_field_arg(%{op: :runtime_call, function: function, args: [inner]}, env)
       when function in [:retain, "retain", "elmc_retain"] and is_map(inner) do
    canonical_field_arg(inner, env)
  end

  defp canonical_field_arg(arg, _env), do: arg

  defp collect_native_field_accesses(expr, env, acc) when is_map(expr) do
    acc =
      case native_field_int_access(expr, env) do
        %{} = field_expr -> [field_expr | acc]
        _ -> acc
      end

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

  defp native_field_int_access(%{op: :field_access, field: field} = expr, env)
       when is_binary(field) do
    canonical = canonical_field_access(expr, env)

    if RecordFields.int_field?(env, canonical.arg, field) and
         not RecordFields.union_tag_field?(env, canonical.arg, field) and
         Host.native_int_expr?(canonical, env) do
      canonical
    else
      nil
    end
  end

  defp native_field_int_access(_expr, _env), do: nil
end
