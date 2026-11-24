defmodule Elmc.Backend.Plan.Lower.SpecialValues.Handheld do
  @moduledoc """
  Special-value handler for `Handheld.*`.

  Command and draw numbers match `elmc/priv/handheld/include/handheld_host.h`.
  This handler is installed only for a handheld target, so Pebble programs
  never see these clauses.
  """

  alias Elmc.Backend.CCodegen.Types, as: Types
  alias Elmc.Backend.Plan.Lower.SpecialValues.Helpers

  @behaviour Elmc.Backend.Plan.Lower.SpecialValues.Handler

  @draw_clear 2
  @draw_pixel 3
  @draw_line 4
  @draw_rect 5
  @draw_fill_rect 6
  @draw_circle 7
  @draw_fill_circle 8
  @draw_text 29
  @cmd_display_metrics 62
  @cmd_module_ready 63
  @cmd_nfc_scan 64
  @cmd_nfc_read 65
  @cmd_ir_send 66
  @cmd_gpio_write 67
  @cmd_gpio_read 68
  @cmd_radio_http_get 69
  @cmd_usb_hid_tap 70
  @cmd_vibes_cancel 13
  @cmd_vibes_short 14
  @cmd_vibes_long 15
  @cmd_vibes_double 16
  @cmd_battery 24
  # Masks match HANDHELD_SUB_* in elmc/priv/handheld/include/handheld_host.h.
  @sub_presses "134217728"
  @sub_taps "268435456"
  @sub_nfc "536870912"
  @sub_button "ELMC_SUBSCRIPTION_BUTTON_RAW"
  @buttons %{
    "A" => 1,
    "B" => 2,
    "Up" => 3,
    "Down" => 4,
    "Left" => 5,
    "Right" => 6,
    "Select" => 7,
    "Back" => 8
  }

  @modules %{
    "Nfc" => 1,
    "Infrared" => 2,
    "Gpio" => 3,
    "Usb" => 4,
    "Radio" => 5,
    "Sensors" => 6
  }

  @keys %{"enter" => 40, "escape" => 41, "tab" => 43, "space" => 44}

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Pkg.app.Handheld." <> rest, args),
    do: special_value_from_target("Handheld." <> rest, args)

  def special_value_from_target("Handheld.Color." <> name, args),
    do: color_value(name, List.wrap(args))

  def special_value_from_target("Handheld.Ui.clear", [color]),
    do: cmd(@draw_clear, [color_expr(color)])

  def special_value_from_target("Handheld.Ui.pixel", [point, color]),
    do: cmd(@draw_pixel, point_params(point) ++ [color_expr(color)])

  def special_value_from_target("Handheld.Ui.line", [from, to, color]),
    do: cmd(@draw_line, point_params(from) ++ point_params(to) ++ [color_expr(color)])

  def special_value_from_target("Handheld.Ui.rect", [bounds, color]),
    do: cmd(@draw_rect, rect_params(bounds) ++ [color_expr(color)])

  def special_value_from_target("Handheld.Ui.fill", [bounds, color]),
    do: cmd(@draw_fill_rect, rect_params(bounds) ++ [color_expr(color)])

  def special_value_from_target("Handheld.Ui.circle", [center, radius, color]),
    do: cmd(@draw_circle, point_params(center) ++ [radius, color_expr(color)])

  def special_value_from_target("Handheld.Ui.fillCircle", [center, radius, color]),
    do: cmd(@draw_fill_circle, point_params(center) ++ [radius, color_expr(color)])

  def special_value_from_target("Handheld.Ui.text", [point, string, color]),
    do: cmd(@draw_text, point_params(point) ++ [color_expr(color), string])

  def special_value_from_target("Handheld.Display.metrics", [to_msg]),
    do: cmd(@cmd_display_metrics, [Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Device.ready", [module, to_msg]),
    do: cmd(@cmd_module_ready, [module_expr(module), Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Nfc.scan", []),
    do: cmd(@cmd_nfc_scan, [])

  def special_value_from_target("Handheld.Nfc.read", []),
    do: cmd(@cmd_nfc_read, [])

  def special_value_from_target("Handheld.Infrared.send", [count]),
    do: cmd(@cmd_ir_send, [count])

  def special_value_from_target("Handheld.Gpio.write", [pin, level]),
    do: cmd(@cmd_gpio_write, [pin, level_expr(level)])

  def special_value_from_target("Handheld.Gpio.read", [pin, to_msg]),
    do: cmd(@cmd_gpio_read, [pin, Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Radio.get", [url]),
    do: cmd(@cmd_radio_http_get, [url])

  def special_value_from_target("Handheld.Usb.tap", [key]),
    do: cmd(@cmd_usb_hid_tap, [key_expr(key)])

  def special_value_from_target("Handheld.Usb." <> name, []),
    do: key_constant(name)

  def special_value_from_target("Handheld.Usb.code", [code]),
    do: code

  def special_value_from_target("Handheld.Vibes.cancel", []),
    do: cmd(@cmd_vibes_cancel, [])

  def special_value_from_target("Handheld.Vibes.shortPulse", []),
    do: cmd(@cmd_vibes_short, [])

  def special_value_from_target("Handheld.Vibes.longPulse", []),
    do: cmd(@cmd_vibes_long, [])

  def special_value_from_target("Handheld.Vibes.doublePulse", []),
    do: cmd(@cmd_vibes_double, [])

  def special_value_from_target("Handheld.Battery.level", [to_msg]),
    do: cmd(@cmd_battery, [Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Input.presses", [to_msg]),
    do: sub(@sub_presses, [Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Input.onPress", [button, msg]) do
    case Map.fetch(@buttons, ctor_name(button)) do
      {:ok, id} ->
        sub(@sub_button, [int(id), int(1), Helpers.constructor_tag_expr(msg)])

      :error ->
        nil
    end
  end

  def special_value_from_target("Handheld.Input.taps", [to_msg]),
    do: sub(@sub_taps, [Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Nfc.onTag", [to_msg]),
    do: sub(@sub_nfc, [Helpers.constructor_tag_expr(to_msg)])

  def special_value_from_target("Handheld.Platform.application", [config]),
    do: %{op: :int_literal, value: 0, keep_alive: [config]}

  def special_value_from_target("Handheld.Platform.application", _args),
    do: %{op: :int_literal, value: 0}

  def special_value_from_target(_target, _args), do: nil

  defp sub(mask, params) when is_binary(mask) and is_list(params) do
    %{op: :pebble_sub, mask: %{op: :c_int_expr, value: mask}, params: params}
  end

  defp ctor_name(expr) do
    case ctor(expr) do
      {name, []} -> name
      _ -> nil
    end
  end

  defp cmd(kind, args) when is_integer(kind) and is_list(args) do
    %{
      op: :pebble_cmd,
      kind: %{op: :c_int_expr, value: Integer.to_string(kind)},
      params: args
    }
  end

  defp color_value("black", []), do: int(0)
  defp color_value("off", []), do: int(0)
  defp color_value("on", []), do: int(1)
  defp color_value("white", []), do: int(65535)

  defp color_value("rgb", [r, g, b]) do
    case {literal(r), literal(g), literal(b)} do
      {r, g, b} when is_integer(r) and is_integer(g) and is_integer(b) ->
        int(rgb565(r, g, b))

      _ ->
        nil
    end
  end

  defp color_value(_name, _args), do: nil

  defp color_expr(expr) do
    case ctor(expr) do
      {"black", []} -> int(0)
      {"off", []} -> int(0)
      {"on", []} -> int(1)
      {"white", []} -> int(65535)
      {"rgb", [r, g, b]} -> color_value("rgb", [r, g, b]) || expr
      _ -> expr
    end
  end

  defp module_expr(expr) do
    case ctor(expr) do
      {name, []} ->
        case Map.fetch(@modules, name) do
          {:ok, id} -> int(id)
          :error -> expr
        end

      _ ->
        expr
    end
  end

  defp level_expr(expr) do
    case ctor(expr) do
      {"Low", []} -> int(0)
      {"High", []} -> int(1)
      _ -> expr
    end
  end

  defp key_constant(name) do
    case Map.fetch(@keys, name) do
      {:ok, code} -> int(code)
      :error -> nil
    end
  end

  defp key_expr(expr) do
    case ctor(expr) do
      {name, []} ->
        case Map.fetch(@keys, name) do
          {:ok, code} -> int(code)
          :error -> expr
        end

      {"code", [code]} ->
        code

      {"Key", [code]} ->
        code

      _ ->
        expr
    end
  end

  defp point_params(point) do
    [Helpers.field_access_expr(point, "x"), Helpers.field_access_expr(point, "y")]
  end

  defp rect_params(rect) do
    [
      Helpers.field_access_expr(rect, "x"),
      Helpers.field_access_expr(rect, "y"),
      Helpers.field_access_expr(rect, "width"),
      Helpers.field_access_expr(rect, "height")
    ]
  end

  defp ctor(%{op: op, target: target} = expr)
       when op in [:qualified_call, :qualified_ref, :qualified_var, :constructor_call, :constructor_ref] and
              is_binary(target) do
    {short(target), Map.get(expr, :args, [])}
  end

  defp ctor(%{op: :int_literal, union_ctor: name}) when is_binary(name), do: {short(name), []}
  defp ctor(_expr), do: nil

  defp short(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp literal(%{op: :int_literal, value: value}) when is_integer(value), do: value
  defp literal(_expr), do: nil

  defp rgb565(r, g, b) do
    red = Bitwise.bsr(clamp(r), 3)
    green = Bitwise.bsr(clamp(g), 2)
    blue = Bitwise.bsr(clamp(b), 3)
    Bitwise.bor(Bitwise.bsl(red, 11), Bitwise.bor(Bitwise.bsl(green, 5), blue))
  end

  defp clamp(n) when is_integer(n), do: n |> max(0) |> min(255)

  defp int(value) when is_integer(value), do: %{op: :int_literal, value: value}
end
