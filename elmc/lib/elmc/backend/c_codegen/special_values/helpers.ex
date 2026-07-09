defmodule Elmc.Backend.CCodegen.SpecialValues.Helpers do
  @moduledoc false

  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.PebbleMsgTag
  alias Elmc.Backend.CCodegen.Subscriptions
  alias Elmc.Backend.CCodegen.SpecialValues.Core
  alias Elmc.Backend.CCodegen.Types

  def draw_kind(kind), do: Elmc.Backend.Pebble.draw_kind_id!(kind)

  def command_kind(kind), do: Elmc.Backend.Pebble.command_kind_id!(kind)

  def command_kind_expr(kind),
    do: %{op: :c_int_expr, value: Elmc.Backend.Pebble.command_kind_c_name!(kind)}

  def encoded_to_msg_cmd(kind, to_msg),
    do: encoded_cmd_expr(command_kind(kind), [constructor_tag_expr(to_msg)], 1)

  def ui_node_kind_expr(kind), do: %{op: :c_int_expr, value: generated_ui_node_kind_macro(kind)}
  def context_kind_expr(kind), do: %{op: :c_int_expr, value: generated_context_kind_macro(kind)}

  def draw_kind_expr(kind), do: %{op: :c_int_expr, value: generated_draw_kind_macro(kind)}

  def generated_draw_kind_macro(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> String.upcase()
    |> then(&"ELMC_RENDER_OP_#{&1}")
  end

  def generated_draw_kind_macro(kind) when is_integer(kind) do
    kind
    |> Elmc.Backend.Pebble.draw_kind_c_name!()
    |> String.replace_prefix("ELMC_PEBBLE_DRAW_", "ELMC_RENDER_OP_")
  end

  def generated_ui_node_kind_macro(:window_stack), do: "ELMC_UI_NODE_WINDOW_STACK"
  def generated_ui_node_kind_macro(:window_node), do: "ELMC_UI_NODE_WINDOW"
  def generated_ui_node_kind_macro(:canvas_layer), do: "ELMC_UI_NODE_CANVAS_LAYER"

  def generated_context_kind_macro(:stroke_width), do: "ELMC_CONTEXT_STROKE_WIDTH"
  def generated_context_kind_macro(:antialiased), do: "ELMC_CONTEXT_ANTIALIASED"
  def generated_context_kind_macro(:stroke_color), do: "ELMC_CONTEXT_STROKE_COLOR"
  def generated_context_kind_macro(:fill_color), do: "ELMC_CONTEXT_FILL_COLOR"
  def generated_context_kind_macro(:text_color), do: "ELMC_CONTEXT_TEXT_COLOR"
  def generated_context_kind_macro(:compositing_mode), do: "ELMC_CONTEXT_COMPOSITING_MODE"

  def text_options_special_arg(%{op: :var} = options), do: options

  def text_options_special_arg(options),
    do: Elmc.Backend.CCodegen.Host.text_options_expr(options)

  def subscription_special_value(target, args) do
    case Subscriptions.subscription_sub_expr(target, args) do
      nil -> %{op: :unsupported}
      expr -> expr
    end
  end

  @spec encoded_cmd_expr(non_neg_integer(), [Types.ir_expr()], non_neg_integer()) ::
          Types.ir_expr()
  def encoded_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      if pebble_cmd_eligible?(args) do
        %{op: :pebble_cmd, kind: command_kind_expr(kind), params: args}
      else
        encoded_cmd_as_tuple(command_kind_expr(kind), args)
      end
    else
      %{op: :unsupported}
    end
  end

  # Draw op ids overlap runtime command ids (e.g. fill_circle and get_clock_style_24h are
  # both 8). Field-expanded draw args must always encode as render-op tuples, never
  # :pebble_cmd with command_kind_expr/1.
  @spec encoded_draw_field_cmd_expr(non_neg_integer(), [Types.ir_expr()], non_neg_integer()) ::
          Types.ir_expr()
  def encoded_draw_field_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      if render_cmd_eligible?(args) do
        %{op: :render_cmd, kind: draw_kind_expr(kind), params: args}
      else
        encoded_cmd_as_tuple(draw_kind_expr(kind), args)
      end
    else
      %{op: :unsupported}
    end
  end

  @spec encoded_cmd_as_tuple(Types.ir_expr(), [Types.ir_expr()]) :: Types.ir_expr()
  def encoded_cmd_as_tuple(kind_expr, args) when is_list(args) do
    arity = length(args)
    payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
    %{op: :tuple2, left: kind_expr, right: tuple_chain(payload)}
  end

  defp pebble_cmd_eligible?(args) do
    length(args) <= 5 and Enum.all?(args, &pebble_cmd_param?/1)
  end

  defp pebble_cmd_param?(%{op: op}) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp pebble_cmd_param?(%{op: :var}), do: true
  defp pebble_cmd_param?(%{op: :call}), do: true
  defp pebble_cmd_param?(%{op: :runtime_call}), do: true
  defp pebble_cmd_param?(%{op: :field_access}), do: true
  defp pebble_cmd_param?(%{op: :if}), do: true
  defp pebble_cmd_param?(%{op: :case}), do: true
  defp pebble_cmd_param?(%{op: :let_in}), do: true
  defp pebble_cmd_param?(%{op: :compare}), do: true
  defp pebble_cmd_param?(%{op: :add_const}), do: true
  defp pebble_cmd_param?(%{op: :add_vars}), do: true
  defp pebble_cmd_param?(%{op: :sub_const}), do: true

  defp pebble_cmd_param?(%{op: :constructor_call, args: args}) when is_list(args),
    do: Enum.all?(args, &pebble_cmd_param?/1)

  defp pebble_cmd_param?(%{op: :qualified_call, args: args}) when is_list(args),
    do: Enum.all?(args, &pebble_cmd_param?/1)

  defp pebble_cmd_param?(%{op: :record_literal, fields: fields}) when is_list(fields),
    do: Enum.all?(fields, fn %{expr: expr} -> pebble_cmd_param?(expr) end)

  defp pebble_cmd_param?(_), do: false

  defp render_cmd_eligible?(args) do
    length(args) <= 6 and Enum.all?(args, &pebble_cmd_param?/1)
  end

  @spec encoded_draw_cmd_expr(non_neg_integer(), [Types.ir_expr()], non_neg_integer()) ::
          Types.ir_expr()
  def encoded_draw_cmd_expr(kind, args, arity) do
    if length(args) == arity do
      if render_cmd_eligible?(args) do
        %{op: :render_cmd, kind: draw_kind_expr(kind), params: args}
      else
        payload = args ++ List.duplicate(%{op: :int_literal, value: 0}, max(0, 6 - arity))
        %{op: :tuple2, left: draw_kind_expr(kind), right: tuple_chain(payload)}
      end
    else
      %{op: :unsupported}
    end
  end

  @spec encoded_text_cmd_expr(non_neg_integer(), [Types.ir_expr()]) :: Types.ir_expr()
  def encoded_text_cmd_expr(kind, args) when is_list(args) and length(args) >= 2 do
    {value, payload} = List.pop_at(args, -1)

    if render_text_cmd_eligible?(payload, value) do
      %{
        op: :render_text_cmd,
        kind: draw_kind_expr(kind),
        int_params: payload,
        text: value
      }
    else
      %{op: :tuple2, left: draw_kind_expr(kind), right: tuple_chain(payload ++ [value])}
    end
  end

  def encoded_text_cmd_expr(_kind, _args), do: %{op: :unsupported}

  defp render_text_cmd_eligible?(payload, text) do
    length(payload) == 6 and
      Enum.all?(payload, &render_text_int_param?/1) and
      render_text_value_param?(text)
  end

  defp render_text_int_param?(%{op: op}) when op in [:int_literal, :c_int_expr, :msg_tag_expr],
    do: true

  defp render_text_int_param?(%{op: :var}), do: true
  defp render_text_int_param?(%{op: :field_access}), do: true
  defp render_text_int_param?(%{op: :if}), do: true
  defp render_text_int_param?(%{op: :call}), do: true
  defp render_text_int_param?(%{op: :runtime_call}), do: true
  defp render_text_int_param?(%{op: :compare}), do: true
  defp render_text_int_param?(%{op: op}) when op in [:add_const, :sub_const, :add_vars], do: true

  defp render_text_int_param?(%{op: :constructor_call, args: args}) when is_list(args),
    do: Enum.all?(args, &render_text_int_param?/1)

  defp render_text_int_param?(%{op: :qualified_call, args: args}) when is_list(args),
    do: Enum.all?(args, &render_text_int_param?/1)

  defp render_text_int_param?(%{op: :record_literal, fields: fields}) when is_list(fields),
    do: Enum.all?(fields, fn %{expr: expr} -> render_text_int_param?(expr) end)

  defp render_text_int_param?(_), do: false

  defp render_text_value_param?(%{op: op})
       when op in [
              :string_literal,
              :var,
              :string_append,
              :int_literal,
              :constructor_call,
              :qualified_call,
              :call,
              :runtime_call,
              :if,
              :case,
              :let_in
            ],
       do: true

  defp render_text_value_param?(_), do: false

  def text_alignment_expr(:left), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_LEFT"}
  def text_alignment_expr(:center), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_CENTER"}
  def text_alignment_expr(:right), do: %{op: :c_int_expr, value: "ELMC_TEXT_ALIGN_RIGHT"}

  def text_overflow_expr(:word_wrap),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_WORD_WRAP"}

  def text_overflow_expr(:trailing_ellipsis),
    do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS"}

  def text_overflow_expr(:fill), do: %{op: :c_int_expr, value: "ELMC_TEXT_OVERFLOW_FILL"}

  @spec tuple_chain([Types.ir_expr()]) :: Types.ir_expr()
  def tuple_chain([single]), do: single

  def tuple_chain([head | rest]) do
    %{op: :tuple2, left: head, right: tuple_chain(rest)}
  end

  def health_metric_to_kernel_expr(%{op: :constructor_call, target: target, args: []})
       when is_binary(target) do
    %{
      op: :int_literal,
      value: Map.get(IRQueries.bundled_health_metric_kernel_values(), target, 0)
    }
  end

  def health_metric_to_kernel_expr(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{op: :int_literal, value: value}

  def health_metric_to_kernel_expr(metric) when is_map(metric), do: metric

  def runtime_fn_lambda(function, arg_names) when is_binary(function) and is_list(arg_names) do
    %{
      op: :lambda,
      args: arg_names,
      body: %{
        op: :runtime_call,
        function: function,
        args: Enum.map(arg_names, &%{op: :var, name: &1})
      }
    }
  end

  @spec http_request_constructor_expr(String.t(), Types.ir_expr(), Types.ir_expr()) ::
          Types.ir_expr()
  def http_request_constructor_expr(method_ctor, url, to_msg) do
    method = %{op: :constructor_call, target: "Pebble.Http.#{method_ctor}", args: []}

    req =
      %{
        op: :record_literal,
        fields: [
          {"method", method},
          {"url", url},
          {"headers", %{op: :list_literal, items: []}},
          {"body", %{op: :constructor_call, target: "Nothing", args: []}},
          {"timeout", %{op: :constructor_call, target: "Nothing", args: []}}
        ]
      }

    %{op: :constructor_call, target: "Pebble.Http.Request", args: [req, to_msg]}
  end

  @spec constructor_tag_expr(Types.ir_expr()) :: Types.ir_expr()
  def constructor_tag_expr(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    msg_tag_expr(ctor)
  end

  def constructor_tag_expr(%{op: :int_literal, value: value}) when is_integer(value) do
    %{op: :int_literal, value: value}
  end

  def constructor_tag_expr(%{op: :var, name: name}) when is_binary(name) do
    if msg_constructor_name?(name), do: msg_tag_expr(name), else: %{op: :int_literal, value: 0}
  end

  def constructor_tag_expr(%{op: :qualified_ref, target: target}) when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  def constructor_tag_expr(%{op: :qualified_var, target: target}) when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  def constructor_tag_expr(%{op: :constructor_call, target: target, args: []})
       when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  def constructor_tag_expr(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    if msg_constructor_name?(target),
      do: msg_tag_expr(target),
      else: %{op: :int_literal, value: 0}
  end

  def constructor_tag_expr(%{op: :partial_constructor, target: target, args: []})
       when is_binary(target) do
    %{op: :msg_tag_expr, name: constructor_short_name(target)}
  end

  def constructor_tag_expr(_), do: %{op: :int_literal, value: 0}

  def animation_id_int_expr(%{op: :int_literal, union_ctor: ctor, value: value})
       when is_binary(ctor) and is_integer(value) do
    %{op: :int_literal, value: value}
  end

  def animation_id_int_expr(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{op: :int_literal, value: value}

  def animation_id_int_expr(%{op: :field_access} = expr), do: expr
  def animation_id_int_expr(%{op: :var} = expr), do: expr
  def animation_id_int_expr(expr), do: expr

  defp msg_constructor_name?(name) when is_binary(name) do
    short = constructor_short_name(name)
    PebbleMsgTag.msg_constructor?(short) or PebbleMsgTag.msg_constructor?(name)
  end

  def msg_tag_expr(name) when is_binary(name) do
    %{op: :msg_tag_expr, name: constructor_short_name(name)}
  end

  def constructor_short_name(name) do
    name |> String.split(".") |> List.last()
  end

  @spec constructor_tag(String.t()) :: non_neg_integer()
  def constructor_tag(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    Map.get_lazy(tags, name, fn ->
      name
      |> String.split(".")
      |> List.last()
      |> then(&Map.get(tags, &1, 0))
    end)
  end

  @spec point_coord_exprs(Types.ir_expr()) :: {:ok, {Types.ir_expr(), Types.ir_expr()}} | :error
  def point_coord_exprs(%{op: :record_literal, fields: fields}) when is_list(fields) do
    with %{expr: x} <- Enum.find(fields, &(&1.name == "x")),
         %{expr: y} <- Enum.find(fields, &(&1.name == "y")) do
      {:ok, {x, y}}
    else
      _ -> :error
    end
  end

  def point_coord_exprs(center) when is_map(center) do
    {:ok, {field_access_expr(center, "x"), field_access_expr(center, "y")}}
  end

  def point_coord_exprs(_), do: :error

  @spec encoded_draw_center_cmd_expr(non_neg_integer(), Types.ir_expr(), [Types.ir_expr()], non_neg_integer()) ::
          Types.ir_expr()
  def encoded_draw_center_cmd_expr(kind, center, trailing_args, arity) do
    case point_coord_exprs(center) do
      {:ok, {x, y}} -> encoded_draw_field_cmd_expr(kind, [x, y | trailing_args], arity)
      :error -> %{op: :unsupported}
    end
  end

  @spec encoded_draw_line_cmd_expr(non_neg_integer(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) ::
          Types.ir_expr()
  def encoded_draw_line_cmd_expr(kind, start_pos, end_pos, color) do
    with {:ok, {sx, sy}} <- point_coord_exprs(start_pos),
         {:ok, {ex, ey}} <- point_coord_exprs(end_pos) do
      encoded_draw_field_cmd_expr(kind, [sx, sy, ex, ey, color], 5)
    else
      _ -> %{op: :unsupported}
    end
  end

  @spec field_access_expr(Types.ir_expr(), String.t()) :: Types.ir_expr()
  def field_access_expr(arg_expr, field) when is_map(arg_expr) and is_binary(field) do
    %{op: :field_access, arg: arg_expr, field: field}
  end

  @spec text_options_update_expr(Types.ir_expr(), String.t(), Types.ir_expr()) ::
          Types.ir_expr()
  def text_options_update_expr(options, field, value)
       when is_map(options) and is_binary(field) and is_map(value) do
    %{
      op: :record_update,
      base: options,
      fields: [%{name: field, expr: value}]
    }
  end

  def text_options_update_expr(_options, _field, _value), do: %{op: :unsupported}

  @spec platform_union_is_constructor(Types.ir_expr(), String.t(), non_neg_integer(), String.t()) ::
          Types.ir_expr()
  def platform_union_is_constructor(shape, name, tag, platform_static_macro)
       when is_map(shape) and is_binary(name) and is_integer(tag) and is_binary(platform_static_macro) do
    %{
      op: :case,
      subject: shape,
      branches: [
        %{
          pattern: %{kind: :constructor, name: name, tag: tag, arg_pattern: nil},
          expr: %{op: :int_literal, value: 1}
        },
        %{
          pattern: %{kind: :wildcard},
          expr: %{op: :int_literal, value: 0}
        }
      ]
    }
    |> maybe_put_platform_static_macro(platform_static_macro)
  end

  def maybe_put_platform_static_macro(expr, macro) when is_binary(macro),
    do: Map.put(expr, :platform_static_macro, macro)

  @spec tagged_value_expr(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()
  def tagged_value_expr(tag, value_expr) when is_map(tag) and is_map(value_expr) do
    %{op: :tuple2, left: tag, right: value_expr}
  end

  @spec rotation_expr(Types.ir_expr()) :: Types.ir_expr()
  def rotation_expr(angle_expr) when is_map(angle_expr) do
    tagged_value_expr(
      %{op: :int_literal, value: 1, union_ctor: "Pebble.Ui.Rotation"},
      angle_expr
    )
  end

  @spec compile_time_pebble_angle_expr(Types.ir_expr()) :: {:ok, Types.ir_expr()} | :error
  def compile_time_pebble_angle_expr(%{op: :tuple2, left: left, right: right}) do
    if rotation_union_payload?(left), do: {:ok, right}, else: :error
  end

  def compile_time_pebble_angle_expr(_rotation), do: :error

  @spec pebble_angle_from_degrees(number()) :: integer()
  def pebble_angle_from_degrees(degrees), do: round(degrees * 65_536 / 360)

  def rotation_to_pebble_angle_call(rotation) do
    %{op: :qualified_call, target: "Pebble.Ui.rotationToPebbleAngle", args: [rotation]}
  end

  defp rotation_union_payload?(%{op: :c_int_expr, value: "ELMC_UNION_ROTATION"}), do: true

  defp rotation_union_payload?(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    ctor
    |> String.split(".")
    |> List.last()
    |> Kernel.==("Rotation")
  end

  defp rotation_union_payload?(_left), do: false

  @spec path_expr(Types.ir_expr(), Types.ir_expr(), Types.ir_expr(), Types.ir_expr()) ::
          Types.ir_expr()
  def path_expr(points, offset_x, offset_y, rotation) do
    %{
      op: :tuple2,
      left: points,
      right: %{
        op: :tuple2,
        left: offset_x,
        right: %{
          op: :tuple2,
          left: offset_y,
          right: Core.pebble_angle_expr(rotation)
        }
      }
    }
  end

  def unary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__x"],
      body: %{op: :runtime_call, function: function, args: [%{op: :var, name: "__x"}]}
    }
  end

  def binary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [%{op: :var, name: "__a"}, %{op: :var, name: "__b"}]
      }
    }
  end

  def bound_binary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}]
      }
    }
  end

  def ternary_runtime_lambda(function) do
    %{
      op: :lambda,
      args: ["__a", "__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [
          %{op: :var, name: "__a"},
          %{op: :var, name: "__b"},
          %{op: :var, name: "__c"}
        ]
      }
    }
  end

  def bound_ternary_runtime_lambda(function, first) do
    %{
      op: :lambda,
      args: ["__b", "__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, %{op: :var, name: "__b"}, %{op: :var, name: "__c"}]
      }
    }
  end

  def bound_ternary_runtime_lambda(function, first, second) do
    %{
      op: :lambda,
      args: ["__c"],
      body: %{
        op: :runtime_call,
        function: function,
        args: [first, second, %{op: :var, name: "__c"}]
      }
    }
  end
end
