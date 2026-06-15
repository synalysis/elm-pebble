defmodule Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @spec packed_expr(Types.ir_expr()) :: Types.packed_text_options_result()
  def packed_expr(value_expr) do
    case value_expr do
      %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr} ->
        with {:ok, then_value} <- packed_c_value(then_expr),
             {:ok, else_value} <- packed_c_value(else_expr) do
          if then_value == else_value do
            {:ok, %{op: :c_int_expr, value: then_value}}
          else
            {:ok,
             %{
               op: :direct_native_if,
               cond: cond,
               then_expr: %{op: :c_int_expr, value: then_value},
               else_expr: %{op: :c_int_expr, value: else_value}
             }}
          end
        else
          _ -> :error
        end

      _ ->
        case packed_c_value(value_expr) do
          {:ok, value} -> {:ok, %{op: :c_int_expr, value: value}}
          :error -> :error
        end
    end
  end

  @spec let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: boolean()
  def let?(_name, value_expr, _in_expr, _env) do
    value_shape?(value_expr) and match?({:ok, _}, packed_expr(value_expr))
  end

  @spec value?(Types.ir_expr()) :: boolean()
  def value?(value_expr), do: value_shape?(value_expr)

  @spec packable_value?(Types.ir_expr()) :: boolean()
  def packable_value?(value_expr),
    do: value_shape?(value_expr) and match?({:ok, _}, packed_expr(value_expr))

  @spec expr(Types.ir_expr()) :: Types.ir_expr()
  def expr(%{op: :qualified_call, target: target, args: args}) when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil ->
        %{op: :unsupported}

      rewritten ->
        expr(rewritten)
    end
  end

  def expr(%{op: :call, name: name, args: args}) when is_binary(name) do
    expr(%{op: :qualified_call, target: name, args: args})
  end

  def expr(%{op: :record_literal} = options), do: expr_from_static_record(options)
  def expr(%{op: :record_update} = options), do: expr_from_static_record(options)
  def expr(%{op: :var} = options), do: options

  @spec arg(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) :: Types.ir_expr()
  def arg(%{op: :var, name: name}, env, _counter) do
    case EnvBindings.native_int_binding(env, name) do
      ref when is_binary(ref) -> %{op: :c_int_expr, value: ref}
      _ -> expr(%{op: :var, name: name})
    end
  end

  def arg(options, _env, _counter), do: expr(options)

  defp packed_c_value(expr) do
    expr =
      case expr do
        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          Host.special_value_from_target(Host.normalize_special_target(target), args || []) ||
            expr

        %{op: :call, name: name, args: args} when is_binary(name) ->
          Host.special_value_from_target(name, args || []) || expr

        _ ->
          expr
      end

    case expr(expr) do
      %{op: :c_int_expr, value: value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp value_shape?(%{op: :qualified_call, target: target, args: args}) when is_binary(target) do
    case Host.normalize_special_target(target) do
      "Pebble.Ui.defaultTextOptions" ->
        true

      target
      when target in [
             "Pebble.Ui.alignLeft",
             "Pebble.Ui.alignCenter",
             "Pebble.Ui.alignRight",
             "Pebble.Ui.wordWrap",
             "Pebble.Ui.trailingEllipsis",
             "Pebble.Ui.fillOverflow"
           ] ->
        value_shape?(List.first(args || []))

      _ ->
        false
    end
  end

  defp value_shape?(%{op: :call, name: name, args: args}) when is_binary(name) do
    value_shape?(%{op: :qualified_call, target: name, args: args})
  end

  defp value_shape?(%{op: :if, then_expr: then_expr, else_expr: else_expr}),
    do: value_shape?(then_expr) and value_shape?(else_expr)

  defp value_shape?(%{op: :record_literal, fields: fields}) when is_list(fields),
    do: record_fields?(fields)

  defp value_shape?(%{op: :record_update, base: base, fields: fields}) when is_list(fields) do
    record_fields?(fields) or value_shape?(base)
  end

  defp value_shape?(_), do: false

  @spec register_hoisted_aliases(Types.ir_expr(), String.t()) :: :ok
  def register_hoisted_aliases(expr, ref) when is_binary(ref) do
    expr
    |> hoisted_alias_exprs()
    |> Enum.each(&Host.register_hoisted_native_int(&1, ref))

    register_packed_value_aliases(expr, ref)
    :ok
  end

  defp register_packed_value_aliases(expr, ref) do
    case packed_expr(expr) do
      {:ok, %{op: :c_int_expr, value: value}} ->
        Host.register_hoisted_native_int(%{op: :c_int_expr, value: value}, ref)

      {:ok, %{op: :direct_native_if, then_expr: then_expr, else_expr: else_expr}} ->
        case {packed_c_value(then_expr), packed_c_value(else_expr)} do
          {{:ok, then_value}, {:ok, else_value}} when then_value == else_value ->
            Host.register_hoisted_native_int(%{op: :c_int_expr, value: then_value}, ref)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp hoisted_alias_exprs(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    case {packed_c_value(then_expr), packed_c_value(else_expr)} do
      {{:ok, then_value}, {:ok, else_value}} when then_value == else_value ->
        hoisted_alias_exprs(then_expr)

      _ ->
        []
    end
  end

  defp hoisted_alias_exprs(expr), do: [expr]

  defp record_fields?(fields) do
    fields
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Kernel.==(["alignment", "overflow"])
  end

  defp expr_from_static_record(options) do
    alignment = Expr.record_field_expr(options, "alignment")
    overflow = Expr.record_field_expr(options, "overflow")

    case {alignment, overflow} do
      {%{op: :c_int_expr, value: align_value}, %{op: :c_int_expr, value: overflow_value}}
      when is_binary(align_value) and is_binary(overflow_value) ->
        %{
          op: :c_int_expr,
          value:
            "(#{align_value} + (#{overflow_value} * (1 << ELMC_TEXT_OVERFLOW_SHIFT)))"
        }

      _ ->
        %{
          op: :call,
          name: "__add__",
          args: [
            alignment || SpecialValues.field_access_expr(options, "alignment"),
            %{
              op: :call,
              name: "__mul__",
              args: [
                overflow || SpecialValues.field_access_expr(options, "overflow"),
                %{op: :c_int_expr, value: "(1 << ELMC_TEXT_OVERFLOW_SHIFT)"}
              ]
            }
          ]
        }
    end
  end
end
