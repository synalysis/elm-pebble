defmodule Elmc.Backend.CCodegen.Subscriptions do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Types

  @spec clamp_frame_interval_ms(integer()) :: pos_integer()
  def clamp_frame_interval_ms(ms) when is_integer(ms) do
    ms
    |> max(1)
    |> min(32_767)
  end

  @spec single_subscription_expr(String.t(), [Types.ir_expr()]) :: Types.ir_expr() | nil
  def single_subscription_expr(target, args \\ []) when is_binary(target) do
    subscription_sub_expr(target, args)
  end

  @spec subscription_sub_expr(String.t(), [Types.ir_expr()]) :: Types.ir_expr() | nil
  def subscription_sub_expr(target, args \\ []) when is_binary(target) do
    case subscription_mask_c_expr(target, args) do
      nil ->
        nil

      mask_c_expr ->
        params = subscription_sub_params(target, args)

        if subscription_params_valid?(args, params) and pebble_sub_eligible?(params) do
          %{
            op: :pebble_sub,
            mask: %{op: :c_int_expr, value: mask_c_expr},
            params: params
          }
        else
          nil
        end
    end
  end

  @spec subscription_batch_expr([Types.ir_expr()]) :: Types.ir_expr() | nil
  def subscription_batch_expr([%{op: :list_literal, items: items}]) do
    batch_items = Enum.flat_map(items, &batch_list_item_expr/1)

    if batch_items == [] do
      nil
    else
      %{op: :list_literal, items: batch_items}
    end
  end

  def subscription_batch_expr(_), do: nil

  defp batch_list_item_expr(item) do
    case subscription_item_sub_expr(item) do
      :none -> []
      sub when is_map(sub) -> [sub]
      nil -> [item]
    end
  end

  defp subscription_item_sub_expr(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    merge_optional_subscription_item(
      subscription_item_sub_expr(then_expr),
      subscription_item_sub_expr(else_expr)
    )
  end

  defp subscription_item_sub_expr(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    case SpecialValues.normalize_special_target(target) do
      t when t in ["Sub.none", "Platform.Sub.none"] ->
        :none

      "Pebble.Frame.every" ->
        subscription_sub_expr("Pebble.Frame.every", args)

      "Pebble.Frame.atFps" ->
        subscription_sub_expr("Pebble.Frame.atFps", args)

      "Elm.Kernel.PebbleWatch.onFrame" ->
        subscription_sub_expr("Elm.Kernel.PebbleWatch.onFrame", args)

      normalized ->
        subscription_sub_expr(normalized, args)
    end
  end

  defp subscription_item_sub_expr(_), do: nil

  defp merge_optional_subscription_item(:none, sub) when is_map(sub), do: sub
  defp merge_optional_subscription_item(sub, :none) when is_map(sub), do: sub
  defp merge_optional_subscription_item(sub, sub) when is_map(sub), do: sub
  defp merge_optional_subscription_item(_, _), do: nil

  @button_event_sub_targets ~w(
    Pebble.Button.onPress
    Pebble.Button.onRelease
    Pebble.Button.onLongPress
  )

  @spec subscription_sub_params(String.t(), [Types.ir_expr()]) :: [Types.ir_expr()]
  def subscription_sub_params(target, args) when is_binary(target) and is_list(args) do
    case SpecialValues.normalize_special_target(target) do
      normalized when normalized in @button_event_sub_targets ->
        button_event_sub_params(args, button_event_for_target(normalized))

      "Pebble.Button.on" ->
        button_raw_sub_params(args)

      "Elm.Kernel.PebbleWatch.onButtonRaw" ->
        button_raw_sub_params(args)

      _ ->
        case List.last(args) do
          nil -> []
          to_msg -> [SpecialValues.msg_tag_param(to_msg)]
        end
    end
  end

  defp button_event_for_target("Pebble.Button.onPress"), do: :pressed
  defp button_event_for_target("Pebble.Button.onRelease"), do: :released
  defp button_event_for_target("Pebble.Button.onLongPress"), do: :long_pressed

  defp button_event_sub_params([button, msg], event) do
    with btn when not is_nil(btn) <- button_int_expr(button),
         %{op: :msg_tag_expr} = tag <- SpecialValues.msg_tag_param(msg) do
      [btn, button_event_expr(event), tag]
    else
      _ -> []
    end
  end

  defp button_raw_sub_params([button, event, msg]) do
    with btn when not is_nil(btn) <- button_int_expr(button),
         evt when not is_nil(evt) <- button_event_int_expr(event),
         %{op: :msg_tag_expr} = tag <- SpecialValues.msg_tag_param(msg) do
      [btn, evt, tag]
    else
      _ -> []
    end
  end

  defp button_raw_sub_params(_), do: []

  defp button_event_expr(:pressed), do: %{op: :c_int_expr, value: "ELMC_BUTTON_EVENT_PRESSED"}
  defp button_event_expr(:released), do: %{op: :c_int_expr, value: "ELMC_BUTTON_EVENT_RELEASED"}
  defp button_event_expr(:long_pressed), do: %{op: :c_int_expr, value: "ELMC_BUTTON_EVENT_LONG_PRESSED"}

  defp button_int_expr(%{op: :c_int_expr, value: value}) when is_binary(value),
    do: %{op: :c_int_expr, value: value}

  defp button_int_expr(expr) do
    case button_ctor_short_name(expr) do
      "Back" -> %{op: :c_int_expr, value: "ELMC_BUTTON_BACK"}
      "Up" -> %{op: :c_int_expr, value: "ELMC_BUTTON_UP"}
      "Select" -> %{op: :c_int_expr, value: "ELMC_BUTTON_SELECT"}
      "Down" -> %{op: :c_int_expr, value: "ELMC_BUTTON_DOWN"}
      _ -> button_plain_int_expr(expr)
    end
  end

  defp button_plain_int_expr(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{op: :int_literal, value: value}

  defp button_plain_int_expr(_), do: nil

  defp button_event_int_expr(%{op: :int_literal, value: value}) when is_integer(value),
    do: %{op: :int_literal, value: value}

  defp button_event_int_expr(expr) do
    case button_ctor_short_name(expr) do
      "Pressed" -> button_event_expr(:pressed)
      "Released" -> button_event_expr(:released)
      "LongPressed" -> button_event_expr(:long_pressed)
      _ -> nil
    end
  end

  defp button_ctor_short_name(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor),
    do: ctor |> String.split(".") |> List.last()

  defp button_ctor_short_name(%{op: :qualified_call, target: target, args: []})
       when is_binary(target),
       do: target |> String.split(".") |> List.last()

  defp button_ctor_short_name(%{op: :qualified_var, target: target}) when is_binary(target),
    do: target |> String.split(".") |> List.last()

  defp button_ctor_short_name(%{op: :constructor_call, target: target, args: []})
       when is_binary(target),
       do: target |> String.split(".") |> List.last()

  defp button_ctor_short_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp button_ctor_short_name(_), do: nil

  defp subscription_mask_c_expr(target, args) do
    subscription_item_c_expr(%{op: :qualified_call, target: target, args: args})
  end

  defp subscription_params_valid?([], []), do: true

  defp subscription_params_valid?(args, params) when args != [] do
    case List.last(params) do
      %{op: :msg_tag_expr} -> true
      _ -> false
    end
  end

  defp pebble_sub_eligible?(params) do
    length(params) <= 5 and Enum.all?(params, &pebble_sub_param?/1)
  end

  defp pebble_sub_param?(%{op: op}) when op in [:int_literal, :c_int_expr, :msg_tag_expr], do: true
  defp pebble_sub_param?(_), do: false

  defp subscription_item_c_expr(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    case SpecialValues.normalize_special_target(target) do
      "Pebble.Frame.every" ->
        frame_subscription_c_expr(args)

      "Pebble.Frame.atFps" ->
        frame_fps_subscription_c_expr(args)

      "Elm.Kernel.PebbleWatch.onFrame" ->
        frame_subscription_c_expr(args)

      normalized ->
        subscription_item_c_expr(%{op: :qualified_call, target: normalized})
    end
  end

  defp subscription_item_c_expr(%{op: :qualified_call, target: target}) when is_binary(target) do
    case SpecialValues.normalize_special_target(target) do
      "Pebble.Events.onSecondChange" -> "ELMC_SUBSCRIPTION_SECOND_CHANGE"
      "Elm.Kernel.PebbleWatch.onSecondChange" -> "ELMC_SUBSCRIPTION_SECOND_CHANGE"
      "Pebble.Events.onHourChange" -> "ELMC_SUBSCRIPTION_HOUR_CHANGE"
      "Elm.Kernel.PebbleWatch.onHourChange" -> "ELMC_SUBSCRIPTION_HOUR_CHANGE"
      "Pebble.Events.onMinuteChange" -> "ELMC_SUBSCRIPTION_MINUTE_CHANGE"
      "Elm.Kernel.PebbleWatch.onMinuteChange" -> "ELMC_SUBSCRIPTION_MINUTE_CHANGE"
      "Pebble.Events.onDayChange" -> "ELMC_SUBSCRIPTION_DAY_CHANGE"
      "Elm.Kernel.PebbleWatch.onDayChange" -> "ELMC_SUBSCRIPTION_DAY_CHANGE"
      "Pebble.Events.onMonthChange" -> "ELMC_SUBSCRIPTION_MONTH_CHANGE"
      "Elm.Kernel.PebbleWatch.onMonthChange" -> "ELMC_SUBSCRIPTION_MONTH_CHANGE"
      "Pebble.Events.onYearChange" -> "ELMC_SUBSCRIPTION_YEAR_CHANGE"
      "Elm.Kernel.PebbleWatch.onYearChange" -> "ELMC_SUBSCRIPTION_YEAR_CHANGE"
      "Pebble.Button.on" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onPress" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onRelease" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Pebble.Button.onLongPress" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Elm.Kernel.PebbleWatch.onButtonRaw" -> "ELMC_SUBSCRIPTION_BUTTON_RAW"
      "Elm.Kernel.PebbleWatch.onButtonUp" -> "ELMC_SUBSCRIPTION_BUTTON_UP"
      "Elm.Kernel.PebbleWatch.onButtonSelect" -> "ELMC_SUBSCRIPTION_BUTTON_SELECT"
      "Elm.Kernel.PebbleWatch.onButtonDown" -> "ELMC_SUBSCRIPTION_BUTTON_DOWN"
      "Elm.Kernel.PebbleWatch.onButtonLongUp" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_UP"
      "Elm.Kernel.PebbleWatch.onButtonLongSelect" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT"
      "Elm.Kernel.PebbleWatch.onButtonLongDown" -> "ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN"
      "Pebble.Accel.onTap" -> "ELMC_SUBSCRIPTION_ACCEL_TAP"
      "Elm.Kernel.PebbleWatch.onAccelTap" -> "ELMC_SUBSCRIPTION_ACCEL_TAP"
      "Pebble.Accel.onData" -> "ELMC_SUBSCRIPTION_ACCEL_DATA"
      "Elm.Kernel.PebbleWatch.onAccelData" -> "ELMC_SUBSCRIPTION_ACCEL_DATA"
      "Pebble.System.onBatteryChange" -> "ELMC_SUBSCRIPTION_BATTERY"
      "Elm.Kernel.PebbleWatch.onBatteryChange" -> "ELMC_SUBSCRIPTION_BATTERY"
      "Pebble.System.onConnectionChange" -> "ELMC_SUBSCRIPTION_CONNECTION"
      "Elm.Kernel.PebbleWatch.onConnectionChange" -> "ELMC_SUBSCRIPTION_CONNECTION"
      "Pebble.Health.onEvent" -> "ELMC_SUBSCRIPTION_HEALTH"
      "Elm.Kernel.PebbleWatch.onHealthEvent" -> "ELMC_SUBSCRIPTION_HEALTH"
      "Pebble.AppFocus.onChange" -> "ELMC_SUBSCRIPTION_APP_FOCUS"
      "Elm.Kernel.PebbleWatch.onAppFocusChange" -> "ELMC_SUBSCRIPTION_APP_FOCUS"
      "Pebble.Compass.onChange" -> "ELMC_SUBSCRIPTION_COMPASS"
      "Elm.Kernel.PebbleWatch.onCompassChange" -> "ELMC_SUBSCRIPTION_COMPASS"
      "Pebble.Dictation.onStatus" -> "ELMC_SUBSCRIPTION_DICTATION"
      "Pebble.Dictation.onResult" -> "ELMC_SUBSCRIPTION_DICTATION"
      "Elm.Kernel.PebbleWatch.onDictationStatus" -> "ELMC_SUBSCRIPTION_DICTATION"
      "Elm.Kernel.PebbleWatch.onDictationResult" -> "ELMC_SUBSCRIPTION_DICTATION"
      "Pebble.UnobstructedArea.onWillChange" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Pebble.UnobstructedArea.onChanging" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Pebble.UnobstructedArea.onDidChange" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Elm.Kernel.PebbleWatch.onUnobstructedWillChange" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Elm.Kernel.PebbleWatch.onUnobstructedChanging" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Elm.Kernel.PebbleWatch.onUnobstructedDidChange" -> "ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA"
      "Companion.Watch.onPhoneToWatch" -> "ELMC_SUBSCRIPTION_APPMESSAGE"
      _ -> nil
    end
  end

  defp frame_subscription_c_expr([%{op: :int_literal, value: ms}, _to_msg]) when is_integer(ms) do
    "(ELMC_SUBSCRIPTION_FRAME_BASE + (#{clamp_frame_interval_ms(ms)} << 16))"
  end

  defp frame_subscription_c_expr(_args), do: nil

  defp frame_fps_subscription_c_expr([%{op: :int_literal, value: fps}, _to_msg])
       when is_integer(fps) do
    "(ELMC_SUBSCRIPTION_FRAME_BASE + (#{clamp_frame_interval_ms(div(1000, max(fps, 1)))} << 16))"
  end

  defp frame_fps_subscription_c_expr(_args), do: nil

  @button_raw_mask "ELMC_SUBSCRIPTION_BUTTON_RAW"

  @batch_targets ~w(
    Pebble.Events.batch
    Elm.Kernel.PebbleWatch.batch
  )

  @type subscription_analysis :: %{
          tag_masks: [String.t()],
          button_raw_count: non_neg_integer(),
          compact: boolean(),
          dynamic?: boolean(),
          has_frame: boolean(),
          model_dependent?: boolean()
        }

  @spec model_dependent?(map() | nil) :: boolean()
  def model_dependent?(nil), do: false

  def model_dependent?(%{args: [param | _], expr: expr})
      when is_binary(param) and not is_nil(expr) do
    param != "_" and expr_uses_param?(expr, param, MapSet.new())
  end

  def model_dependent?(_), do: false

  @spec analyze_subscription_masks(term()) :: subscription_analysis()
  def analyze_subscription_masks(expr) do
    acc = %{tag_masks: [], button_raw_count: 0, dynamic?: false, bindings: %{}}
    acc = collect_subscription_specs(expr, acc)

    {tag_masks, has_frame} =
      acc.tag_masks
      |> Enum.uniq()
      |> Enum.reject(&(&1 == @button_raw_mask))
      |> Enum.map_reduce(false, fn mask, frame? ->
        if frame_mask?(mask) do
          {nil, true}
        else
          {mask, frame?}
        end
      end)
      |> then(fn {masks, frame?} -> {Enum.reject(masks, &is_nil/1), frame?} end)

    compact = not acc.dynamic? and Enum.all?(tag_masks, &static_mask?/1)

    %{
      tag_masks: tag_masks,
      button_raw_count: acc.button_raw_count,
      compact: compact,
      dynamic?: acc.dynamic?,
      has_frame: has_frame
    }
  end

  @spec frame_mask?(String.t()) :: boolean()
  def frame_mask?(mask) when is_binary(mask) do
    String.contains?(mask, "ELMC_SUBSCRIPTION_FRAME_BASE")
  end

  defp static_mask?(mask) when is_binary(mask) do
    not frame_mask?(mask)
  end

  defp collect_subscription_specs(nil, acc), do: acc

  defp collect_subscription_specs(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_subscription_specs/2)
  end

  defp collect_subscription_specs(%{op: :let, bindings: bindings, body: body}, acc) do
    bindings_map =
      Enum.reduce(bindings, Map.get(acc, :bindings, %{}), fn %{name: name, expr: expr}, env ->
        Map.put(env, name, expr)
      end)

    acc = %{acc | bindings: bindings_map}
    collect_subscription_specs(body, acc)
  end

  defp collect_subscription_specs(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr},
         acc
       )
       when is_binary(name) do
    bindings_map = Map.put(Map.get(acc, :bindings, %{}), name, value_expr)
    collect_subscription_specs(in_expr, %{acc | bindings: bindings_map})
  end

  defp collect_subscription_specs(%{op: :if, then_expr: then_expr, else_expr: else_expr}, acc) do
    acc
    |> then(&collect_subscription_specs(then_expr, &1))
    |> then(&collect_subscription_specs(else_expr, &1))
  end

  defp collect_subscription_specs(%{op: :var, name: name}, acc) when is_binary(name) do
    case Map.get(acc, :bindings, %{}) do
      %{^name => expr} -> collect_subscription_specs(expr, acc)
      _ -> %{acc | dynamic?: true}
    end
  end

  defp collect_subscription_specs(%{op: :qualified_call, target: target, args: args}, acc)
       when is_binary(target) and is_list(args) do
    normalized = SpecialValues.normalize_special_target(target)

    cond do
      normalized in ["Sub.none", "Platform.Sub.none"] ->
        acc

      normalized in @batch_targets ->
        case args do
          [%{op: :list_literal, items: items}] ->
            Enum.reduce(items, acc, &collect_subscription_specs/2)

          _ ->
            %{acc | dynamic?: true}
        end

      true ->
        case subscription_sub_expr(normalized, args) do
          %{op: :pebble_sub, mask: %{op: :c_int_expr, value: @button_raw_mask}} ->
            %{acc | button_raw_count: acc.button_raw_count + 1}

          %{op: :pebble_sub, mask: %{op: :c_int_expr, value: mask}} ->
            %{acc | tag_masks: [mask | acc.tag_masks]}

          %{op: :pebble_sub} ->
            %{acc | dynamic?: true}

          nil ->
            if subscription_mask_c_expr(normalized, args) != nil do
              %{acc | dynamic?: true}
            else
              Enum.reduce(args, acc, &collect_subscription_specs/2)
            end
        end
    end
  end

  defp collect_subscription_specs(%{} = expr, acc) do
    expr
    |> Map.values()
    |> Enum.reduce(acc, &collect_subscription_specs/2)
  end

  defp collect_subscription_specs(_expr, acc), do: acc

  defp expr_uses_param?(%{op: :var, name: name}, param, bound) when is_binary(name) do
    name == param and not MapSet.member?(bound, name)
  end

  defp expr_uses_param?(%{op: :field_access, arg: arg, field: _field}, param, bound) do
    expr_uses_param?(arg, param, bound)
  end

  defp expr_uses_param?(
         %{op: :let_in, name: bind, value_expr: value_expr, in_expr: in_expr},
         param,
         bound
       )
       when is_binary(bind) do
    expr_uses_param?(value_expr, param, bound) or
      expr_uses_param?(in_expr, param, MapSet.put(bound, bind))
  end

  defp expr_uses_param?(%{op: :let, bindings: bindings, body: body}, param, bound)
       when is_list(bindings) do
    bound2 =
      Enum.reduce(bindings, bound, fn %{name: name}, acc ->
        if is_binary(name), do: MapSet.put(acc, name), else: acc
      end)

    Enum.any?(bindings, fn %{expr: expr} -> expr_uses_param?(expr, param, bound) end) or
      expr_uses_param?(body, param, bound2)
  end

  defp expr_uses_param?(%{op: :lambda, params: params, body: body}, param, bound)
       when is_list(params) do
    bound2 =
      Enum.reduce(params, bound, fn name, acc ->
        if is_binary(name), do: MapSet.put(acc, name), else: acc
      end)

    expr_uses_param?(body, param, bound2)
  end

  defp expr_uses_param?(name, param, bound) when is_binary(name) do
    name == param and not MapSet.member?(bound, name)
  end

  defp expr_uses_param?(expr, param, bound) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.any?(fn
      value when is_map(value) -> expr_uses_param?(value, param, bound)
      values when is_list(values) -> Enum.any?(values, &expr_uses_param?(&1, param, bound))
      _ -> false
    end)
  end

  defp expr_uses_param?(_, _param, _bound), do: false
end

