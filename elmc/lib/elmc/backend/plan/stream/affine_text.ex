defmodule Elmc.Backend.Plan.Stream.AffineText do
  @moduledoc """
  Generic Plan stream fusion for map/indexedMap whose body is affine
  coordinates plus a text/textInt template.

  IR shape only: no function-name or template gates. Coords may be
  `index * k + b`, the item, or a literal; labels may be a string
  literal or `if item == 0 then lit else String.fromInt item`.
  """
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Lower.SpecialValues
  alias Elmc.Backend.Plan.Stream

  @spec try_compile(atom(), term(), term(), Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :error
  def try_compile(kind, fun, list, ctx, b) when kind in [:map, :indexed_map] do
    indexed? = kind == :indexed_map

    with {:ok, params, body} <- mapper_body(fun, indexed?, ctx),
         {:ok, spec} <- match_text_body(body, params),
         {:ok, source, b1} <- compile_source(list, ctx, b) do
      emit(spec, source, indexed?, ctx, b1)
    else
      _ -> :error
    end
  end

  def try_compile(_, _, _, _, _), do: :error

  defp mapper_body(%{op: :lambda, args: args, body: body}, indexed?, _ctx) do
    cond do
      indexed? and match?([_, _], args) -> {:ok, args, body}
      not indexed? and match?([_], args) -> {:ok, [nil, hd(args)], body}
      true -> :error
    end
  end

  defp mapper_body(%{op: op} = fun, indexed?, ctx)
       when op in [:call, :qualified_call, :var, :qualified_ref] do
    case apply_callee(fun, ctx) do
      {:ok, mod, name, prefix} when prefix == [] ->
        case Map.get(ctx.decl_map || %{}, {mod, name}) do
          %{args: args, expr: body} when is_list(args) and is_map(body) ->
            cond do
              indexed? and length(args) >= 2 ->
                {:ok, Enum.take(args, -2), body}

              not indexed? and args != [] ->
                {:ok, [nil, List.last(args)], body}

              true ->
                :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp mapper_body(_, _, _), do: :error

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

  defp match_text_body(expr, [index_param, item_param]) do
    {expr, bindings} = unwrap_lets(expr, %{})
    expr = unwrap_group(expr)
    params = loop_params(index_param, item_param)

    case rewrite_draw(expr) do
      {:text_int, font, pos, value} ->
        with {:ok, font_ref} <- static_int_ref(font, bindings),
             {:ok, x} <- affine_of(record_field(pos, "x"), params, bindings),
             {:ok, y} <- affine_of(record_field(pos, "y"), params, bindings),
             {:ok, val} <- affine_of(value, params, bindings) do
          {:ok,
           %{
             kind: :text_int,
             kind_macro: SpecialValues.generated_draw_kind_macro(:text_int_with_font),
             font: font_ref,
             x: x,
             y: y,
             value: val
           }}
        end

      {:text, font, options, bounds, label} ->
        with {:ok, font_ref} <- static_int_ref(font, bindings),
             {:ok, opts_ref} <- static_int_ref(options_int(options), bindings),
             {:ok, x} <- affine_of(record_field(bounds, "x"), params, bindings),
             {:ok, y} <- affine_of(record_field(bounds, "y"), params, bindings),
             {:ok, w} <- affine_of(record_field(bounds, "w"), params, bindings),
             {:ok, h} <- affine_of(record_field(bounds, "h"), params, bindings),
             {:ok, label_spec} <- match_label(label, item_param, bindings) do
          {:ok,
           %{
             kind: :text,
             kind_macro: SpecialValues.generated_draw_kind_macro(:text),
             font: font_ref,
             options: opts_ref,
             x: x,
             y: y,
             w: w,
             h: h,
             label: label_spec
           }}
        end

      _ ->
        :error
    end
  end

  defp match_text_body(_, _), do: :error

  defp unwrap_lets(%{op: :let_in, name: name, value_expr: value, in_expr: rest}, bindings)
       when is_binary(name) do
    unwrap_lets(rest, Map.put(bindings, name, value))
  end

  defp unwrap_lets(expr, bindings), do: {expr, bindings}

  defp unwrap_group(%{op: op, args: [inner]} = expr) when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {"Pebble.Ui", "group"} -> unwrap_group(inner)
      _ -> expr
    end
  end

  defp unwrap_group(expr), do: expr

  defp rewrite_draw(%{op: op} = expr) when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {"Pebble.Ui", "textInt"} ->
        case Map.get(expr, :args) do
          [font, pos, value] -> {:text_int, font, pos, value}
          _ -> :error
        end

      {"Pebble.Ui", "text"} ->
        case Map.get(expr, :args) do
          [font, options, bounds, label] -> {:text, font, options, bounds, label}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp rewrite_draw(_), do: :error

  defp options_int(%{op: op} = expr)
       when op in [:call, :qualified_call, :qualified_ref, :qualified_var] do
    target = Map.get(expr, :target) || Map.get(expr, :name)

    case SpecialValues.normalize_special_target(target || "") do
      "Pebble.Ui.defaultTextOptions" ->
        %{
          op: :c_int_expr,
          value:
            "(ELMC_TEXT_ALIGN_CENTER + (ELMC_TEXT_OVERFLOW_WORD_WRAP * (1 << ELMC_TEXT_OVERFLOW_SHIFT)))"
        }

      _ ->
        case SpecialValues.special_value_from_target(
               SpecialValues.normalize_special_target(target),
               List.wrap(Map.get(expr, :args))
             ) do
          nil -> expr
          rewritten -> rewritten
        end
    end
  end

  defp options_int(expr), do: expr

  defp loop_params(index_param, item_param) do
    %{
      index: param_name(index_param),
      item: param_name(item_param)
    }
  end

  defp param_name(nil), do: nil
  defp param_name(name) when is_binary(name), do: name
  defp param_name(_), do: nil

  defp match_label(expr, item_param, bindings) do
    expr = resolve(expr, bindings)

    case expr do
      %{op: :string_literal, value: value} when is_binary(value) ->
        {:ok, {:literal, value}}

      %{op: :if, cond: cond, then_expr: then_e, else_expr: else_e} ->
        match_zero_int_label(cond, then_e, else_e, item_param, bindings)

      %{op: :if, then: then_e, else: else_e, cond: cond} ->
        match_zero_int_label(cond, then_e, else_e, item_param, bindings)

      _ ->
        case string_from_int?(expr, item_param, bindings) do
          true -> {:ok, {:from_int, :item, ""}}
          false -> :error
        end
    end
  end

  defp match_zero_int_label(cond, then_e, else_e, item_param, bindings) do
    then_e = resolve(then_e, bindings)
    else_e = resolve(else_e, bindings)

    with true <- zero_test?(cond, item_param, bindings),
         {:ok, zero_lit} <- string_literal(then_e),
         true <- string_from_int?(else_e, item_param, bindings) do
      {:ok, {:from_int, :item, zero_lit}}
    else
      _ -> :error
    end
  end

  defp zero_test?(%{op: :call, name: name, args: [left, right]}, item, bindings)
       when name in ["__eq__", "==", "eq"] do
    zero_pair?(resolve(left, bindings), resolve(right, bindings), item)
  end

  defp zero_test?(%{op: :compare, kind: :eq, left: left, right: right}, item, bindings) do
    zero_pair?(resolve(left, bindings), resolve(right, bindings), item)
  end

  defp zero_test?(_, _, _), do: false

  defp zero_pair?(left, right, item) do
    (var_name(left) == param_name(item) and literal_int(right) == {:ok, 0}) or
      (var_name(right) == param_name(item) and literal_int(left) == {:ok, 0})
  end

  defp string_from_int?(expr, item, bindings) do
    expr = resolve(expr, bindings)

    case expr do
      %{op: :runtime_call, function: "elmc_string_from_int", args: [value]} ->
        var_name(resolve(value, bindings)) == param_name(item)

      %{op: op, args: [value]} = call when op in [:call, :qualified_call] ->
        case Stream.callee_key(call, nil) do
          {mod, "fromInt"} when mod in ["String", "Elm.Kernel.String"] ->
            var_name(resolve(value, bindings)) == param_name(item)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp string_literal(%{op: :string_literal, value: value}) when is_binary(value),
    do: {:ok, value}

  defp string_literal(_), do: :error

  defp affine_of(nil, _, _), do: :error

  defp affine_of(expr, params, bindings) do
    expr = resolve(expr, bindings)

    cond do
      match?({:ok, _}, literal_int(expr)) ->
        {:ok, value} = literal_int(expr)
        {:ok, {:lit, Integer.to_string(value)}}

      match?({:ok, _}, static_int_ref(expr, bindings)) ->
        {:ok, ref} = static_int_ref(expr, bindings)
        {:ok, {:lit, ref}}

      var_name(expr) == params.index and params.index != nil ->
        {:ok, {:index}}

      var_name(expr) == params.item and params.item != nil ->
        {:ok, {:item}}

      true ->
        affine_op(expr, params, bindings)
    end
  end

  defp affine_op(%{op: :call, name: name, args: [left, right]}, params, bindings)
       when name in ["__mul__", "*"] do
    affine_mul(left, right, params, bindings)
  end

  defp affine_op(%{op: :call, name: name, args: [left, right]}, params, bindings)
       when name in ["__add__", "+"] do
    affine_add(left, right, params, bindings)
  end

  defp affine_op(%{op: :add_const, var: name, value: offset}, params, bindings)
       when is_binary(name) and is_integer(offset) do
    case affine_of(%{op: :var, name: name}, params, bindings) do
      {:ok, base} -> {:ok, {:offset, base, offset}}
      :error -> :error
    end
  end

  defp affine_op(%{op: :mul_const, var: name, value: scale}, params, bindings)
       when is_binary(name) and is_integer(scale) do
    affine_of(%{op: :call, name: "__mul__", args: [%{op: :var, name: name}, %{op: :int_literal, value: scale}]}, params, bindings)
  end

  defp affine_op(%{op: :qualified_call, args: [left, right]} = expr, params, bindings) do
    case Stream.callee_key(expr, nil) do
      {_, name} when name in ["mul", "__mul__", "*"] ->
        affine_mul(left, right, params, bindings)

      {_, name} when name in ["add", "__add__", "+"] ->
        affine_add(left, right, params, bindings)

      _ ->
        :error
    end
  end

  defp affine_op(_, _, _), do: :error

  defp affine_mul(left, right, params, bindings) do
    case {affine_of(left, params, bindings), affine_of(right, params, bindings)} do
      {{:ok, {:index}}, {:ok, {:lit, scale}}} -> {:ok, {:mul, :index, scale_int(scale)}}
      {{:ok, {:item}}, {:ok, {:lit, scale}}} -> {:ok, {:mul, :item, scale_int(scale)}}
      {{:ok, {:lit, scale}}, {:ok, {:index}}} -> {:ok, {:mul, :index, scale_int(scale)}}
      {{:ok, {:lit, scale}}, {:ok, {:item}}} -> {:ok, {:mul, :item, scale_int(scale)}}
      _ -> :error
    end
  end

  defp affine_add(left, right, params, bindings) do
    case {affine_of(left, params, bindings), affine_of(right, params, bindings)} do
      {{:ok, {:lit, n}}, {:ok, base}} -> {:ok, {:offset, base, scale_int(n)}}
      {{:ok, base}, {:ok, {:lit, n}}} -> {:ok, {:offset, base, scale_int(n)}}
      {{:ok, a}, {:ok, b}} -> {:ok, {:add, a, b}}
      _ -> :error
    end
  end

  defp scale_int(n) when is_integer(n), do: n

  defp scale_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {v, ""} -> v
      _ -> 0
    end
  end

  defp compile_source(list, ctx, b) do
    list = unwrap_to_ui_node(list)

    case range_bounds(list) do
      {:ok, lo, hi} ->
        {:ok, {:range_lit, lo, hi}, b}

      :error ->
        value_ctx = %{Context.for_branch_arm(ctx) | stream_mode: false}

        case Expr.compile(list, value_ctx, b) do
          {:ok, reg, b1} when is_integer(reg) -> {:ok, {:list, reg}, b1}
          _ -> :error
        end
    end
  end

  defp unwrap_to_ui_node(%{op: op} = expr) when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {"Pebble.Ui", "toUiNode"} -> expr |> Map.get(:args, []) |> List.first() || expr
      _ -> expr
    end
  end

  defp unwrap_to_ui_node(expr), do: expr

  defp range_bounds(%{op: op, args: [lo, hi]} = expr) when op in [:call, :qualified_call] do
    case Stream.callee_key(expr, nil) do
      {mod, "range"} when mod in ["List", "Elm.Kernel.List"] ->
        case {literal_int(lo), literal_int(hi)} do
          {{:ok, a}, {:ok, b}} -> {:ok, a, b}
          _ -> :error
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

  defp emit(spec, source, indexed?, ctx, b) do
    source_args =
      case source do
        {:range_lit, lo, hi} -> %{source: :range, lo: lo, hi: hi}
        {:list, reg} -> %{source: :list, list: reg}
      end

    args = Map.merge(source_args, %{spec: spec, indexed?: indexed?})
    borrows = if match?({:list, _}, source), do: [elem(source, 1)], else: []
    effects = %{produces: nil, consumes: [], borrows: borrows, fallible: true}
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b

    {_, b2} =
      Builder.emit(b1, :stream_affine_text, %{
        dest: :stream_void,
        args: args,
        effects: effects
      })

    b3 = if wrap_catch?, do: Builder.catch_end(b2), else: b2
    {:ok, :stream_void, b3}
  end

  defp resolve(%{op: :var, name: name} = expr, bindings) when is_binary(name) do
    case Map.get(bindings, name) do
      nil -> expr
      inner -> resolve(inner, bindings)
    end
  end

  defp resolve(expr, _), do: expr

  defp var_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp var_name(_), do: nil

  defp literal_int(%{op: :int_literal, value: v}) when is_integer(v), do: {:ok, v}
  defp literal_int(_), do: :error

  defp static_int_ref(expr, bindings) do
    expr = resolve(expr, bindings)

    cond do
      match?({:ok, _}, literal_int(expr)) ->
        {:ok, v} = literal_int(expr)
        {:ok, Integer.to_string(v)}

      match?(%{op: :c_int_expr, value: v} when is_binary(v), expr) ->
        {:ok, expr.value}

      true ->
        case call_target(expr) do
          target when is_binary(target) ->
            args = List.wrap(Map.get(expr, :args))

            cond do
              ResourceUnion.constructor?(target, args) ->
                {:ok, Integer.to_string(ResourceUnion.slot_index(target))}

              true ->
                case SpecialValues.special_value_from_target(
                       SpecialValues.normalize_special_target(target),
                       args
                     ) do
                  nil -> :error
                  rewritten -> static_int_ref(rewritten, bindings)
                end
            end

          _ ->
            :error
        end
    end
  end

  defp record_field(record, field) when is_binary(field) do
    case record do
      %{op: :record_literal, fields: fields} ->
        field_from_list(fields, field)

      %{op: :field_access, arg: arg, field: ^field} ->
        arg

      _ ->
        %{op: :field_access, arg: record, field: field}
    end
  end

  defp field_from_list(fields, field) do
    case Enum.find(fields, fn f -> Map.get(f, :name) == field end) do
      %{expr: expr} -> expr
      %{value: value} -> value
      _ -> nil
    end
  end

  defp call_target(%{target: target}) when is_binary(target), do: target
  defp call_target(%{name: name}) when is_binary(name), do: name
  defp call_target(_), do: nil
end
