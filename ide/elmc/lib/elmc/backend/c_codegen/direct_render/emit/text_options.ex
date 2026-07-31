defmodule Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types


  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type c_int_expr :: %{required(:op) => :c_int_expr, required(:value) => String.t()}

  @type direct_native_if_expr :: %{
          required(:op) => :direct_native_if,
          required(:cond) => Types.ir_expr(),
          required(:then_expr) => c_int_expr(),
          required(:else_expr) => c_int_expr()
        }

  @type packed_text_option_expr :: c_int_expr() | direct_native_if_expr()

  @type text_option_emit_expr ::
          packed_text_option_expr()
          | %{required(:op) => :unsupported}
          | Types.ir_var_expr()
          | %{required(:op) => :call, required(:name) => String.t(), required(:args) => [Types.ir_expr()]}

  @type static_record_emit_expr ::
          c_int_expr()
          | %{required(:op) => :unsupported}
          | %{required(:op) => :call, required(:name) => String.t(), required(:args) => [Types.ir_expr()]}

  @spec packed_expr(Types.ir_expr()) :: {:ok, packed_text_option_expr()} | :error
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
    # Require text-options shape so board/layout records are never packed as ints.
    value_shape?(value_expr) and match?({:ok, _}, packed_expr(value_expr))
  end

  @spec value?(Types.ir_expr()) :: boolean()
  def value?(value_expr), do: value_shape?(value_expr)

  @spec packable_value?(Types.ir_expr()) :: boolean()
  def packable_value?(value_expr),
    do: value_shape?(value_expr) and match?({:ok, _}, packed_expr(value_expr))

  @spec expr(Types.ir_expr()) :: text_option_emit_expr()
  def expr(%{op: :c_int_expr, value: value} = expr) when is_binary(value), do: expr

  def expr(%{op: :qualified_call, target: target, args: args}) when is_binary(target) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args || []) do
      nil ->
        %{op: :unsupported}

      rewritten ->
        expr(rewritten)
    end
  end

  def expr(%{op: :qualified_ref, target: target}) when is_binary(target) do
    expr(%{op: :qualified_call, target: target, args: []})
  end

  def expr(%{op: :call, name: name, args: args}) when is_binary(name) do
    expr(%{op: :qualified_call, target: name, args: args})
  end

  def expr(%{op: :record_literal} = options), do: expr_from_static_record(options)
  def expr(%{op: :record_update} = options), do: expr_from_static_record(options)
  def expr(%{op: :var} = options), do: options
  def expr(%{op: :unsupported}), do: %{op: :unsupported}
  def expr(_options), do: %{op: :unsupported}

  @spec arg(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) :: text_option_emit_expr()
  def arg(%{op: :var, name: name}, env, _counter) do
    case EnvBindings.native_int_binding(env, name) do
      ref when is_binary(ref) ->
        %{op: :c_int_expr, value: ref}

      _ ->
        case Map.get(env, name) do
          {:direct_fragment, frag} ->
            case packed_expr(frag) do
              {:ok, packed} -> packed
              :error -> packed_from_boxed_ref(name, env)
            end

          ref when is_binary(ref) ->
            %{op: :c_int_expr, value: "elmc_text_options_packed(#{ref})"}

          _ ->
            packed_from_boxed_ref(name, env)
        end
    end
  end

  def arg(options, _env, _counter) do
    case packed_expr(options) do
      {:ok, packed} -> packed
      :error -> expr(options)
    end
  end

  @spec packed_from_boxed_ref(Types.binding_name(), Types.compile_env()) :: c_int_expr()
  defp packed_from_boxed_ref(name, env) do
    case Map.get(env, name) do
      ref when is_binary(ref) ->
        %{op: :c_int_expr, value: "elmc_text_options_packed(#{ref})"}

      _ ->
        # Fall back to left-aligned rather than elmc_as_int(record) → 0 with no overflow bits.
        %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_LEFT"}
    end
  end

  @spec packed_c_value(Types.expr()) :: {:ok, String.t()} | :error

  defp packed_c_value(%{op: :c_int_expr, value: value}) when is_binary(value), do: {:ok, value}

  defp packed_c_value(expr) do
    expr =
      case expr do
        %{op: :qualified_call, target: target, args: args} when is_binary(target) ->
          Host.special_value_from_target(Host.normalize_special_target(target), args || []) ||
            expr

        %{op: :qualified_ref, target: target} when is_binary(target) ->
          Host.special_value_from_target(Host.normalize_special_target(target), []) || expr

        %{op: :call, name: name, args: args} when is_binary(name) ->
          Host.special_value_from_target(name, args || []) || expr

        %{op: :record_update, base: base, fields: fields} = update ->
          case expand_text_options_base(base) do
            ^base -> update
            expanded -> %{update | base: expanded, fields: fields}
          end

        _ ->
          expr
      end

    case expr(expr) do
      %{op: :c_int_expr, value: value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp expand_text_options_base(%{op: :qualified_ref, target: target} = base) when is_binary(target) do
    Host.special_value_from_target(Host.normalize_special_target(target), []) || base
  end

  defp expand_text_options_base(%{op: :qualified_call, target: target, args: args} = base)
       when is_binary(target) do
    Host.special_value_from_target(Host.normalize_special_target(target), args || []) || base
  end

  defp expand_text_options_base(base), do: base

  @spec value_shape?(map() | term()) :: boolean()

  defp value_shape?(%{op: :c_int_expr, value: value}) when is_binary(value), do: true

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

  defp value_shape?(%{op: :qualified_ref, target: target}) when is_binary(target) do
    value_shape?(%{op: :qualified_call, target: target, args: []})
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

  @spec register_packed_value_aliases(Types.expr(), String.t()) :: :ok

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

  @spec hoisted_alias_exprs(Types.expr()) :: [Types.expr()]

  defp hoisted_alias_exprs(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    case {packed_c_value(then_expr), packed_c_value(else_expr)} do
      {{:ok, then_value}, {:ok, else_value}} when then_value == else_value ->
        hoisted_alias_exprs(then_expr)

      _ ->
        []
    end
  end

  defp hoisted_alias_exprs(expr), do: [expr]

  @spec record_fields?(list()) :: boolean()

  defp record_fields?(fields) do
    fields
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Kernel.==(["alignment", "overflow"])
  end

  @spec expr_from_static_record(%{optional(atom()) => term(), op: :record_literal | :record_update}) ::
          static_record_emit_expr()

  defp expr_from_static_record(options) do
    alignment =
      options
      |> Expr.record_field_expr("alignment")
      |> normalize_text_option_field(:alignment)

    overflow =
      options
      |> Expr.record_field_expr("overflow")
      |> normalize_text_option_field(:overflow)

    # Missing fields must not default — arbitrary records (board layout, etc.)
    # would otherwise pack as LEFT+WORD_WRAP.
    case {alignment, overflow} do
      {%{op: :c_int_expr, value: align_value}, %{op: :c_int_expr, value: overflow_value}}
      when is_binary(align_value) and is_binary(overflow_value) ->
        %{
          op: :c_int_expr,
          value:
            "(#{align_value} + (#{overflow_value} * (1 << ELMC_TEXT_OVERFLOW_SHIFT)))"
        }

      {nil, _} ->
        %{op: :unsupported}

      {_, nil} ->
        %{op: :unsupported}

      _ ->
        %{
          op: :call,
          name: "__add__",
          args: [
            alignment,
            %{
              op: :call,
              name: "__mul__",
              args: [
                overflow,
                %{op: :c_int_expr, value: "(1 << ELMC_TEXT_OVERFLOW_SHIFT)"}
              ]
            }
          ]
        }
    end
  end

  defp normalize_text_option_field(nil, _kind), do: nil

  defp normalize_text_option_field(%{op: :c_int_expr, value: value} = expr, _kind)
       when is_binary(value),
       do: expr

  defp normalize_text_option_field(%{op: :int_literal, value: 0}, :alignment),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_LEFT"}

  defp normalize_text_option_field(%{op: :int_literal, value: 1}, :alignment),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_CENTER"}

  defp normalize_text_option_field(%{op: :int_literal, value: 2}, :alignment),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_RIGHT"}

  defp normalize_text_option_field(%{op: :int_literal, value: 0}, :overflow),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_WORD_WRAP"}

  defp normalize_text_option_field(%{op: :int_literal, value: 1}, :overflow),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS"}

  defp normalize_text_option_field(%{op: :int_literal, value: 2}, :overflow),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_FILL"}

  defp normalize_text_option_field(expr, _kind), do: expr
end
