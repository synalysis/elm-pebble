defmodule Elmx.Runtime.Pebble.SpecialValues.Handheld do
  @moduledoc false

  @behaviour Elmx.Runtime.Pebble.SpecialValues.Dispatcher

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  @colors %{
    "black" => 0,
    "off" => 0,
    "on" => 1,
    "white" => 65535
  }

  @keys %{"enter" => 40, "escape" => 41, "tab" => 43, "space" => 44}

  @spec rewrite(String.t(), list()) :: {:ok, map()} | :unmatched
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    target = String.replace_prefix(target, "Pkg.app.", "")

    cond do
      match?("Handheld.Color." <> _, target) and args == [] ->
        color_const(target)

      match?("Handheld.Usb." <> _, target) and args == [] ->
        key_const(target)

      true ->
        rewrite_call(target, args)
    end
  end

  defp color_const("Handheld.Color." <> name) do
    case Map.fetch(@colors, name) do
      {:ok, value} -> {:ok, %{op: :int_literal, value: value}}
      :error -> :unmatched
    end
  end

  defp key_const("Handheld.Usb." <> name) do
    case Map.fetch(@keys, name) do
      {:ok, value} -> {:ok, %{op: :int_literal, value: value}}
      :error -> :unmatched
    end
  end

  defp rewrite_call(target, args) do
    case target do
      "Handheld.Platform.application" ->
        ui_call("elmx_platform_application", args)

      "Handheld.Color.rgb" ->
        ui_call("elmx_handheld_color_rgb", args)

      "Handheld.Ui.clear" ->
        ui_call("elmx_handheld_clear", args)

      "Handheld.Ui.pixel" ->
        ui_call("elmx_handheld_pixel", args)

      "Handheld.Ui.line" ->
        ui_call("elmx_handheld_line", args)

      "Handheld.Ui.rect" ->
        ui_call("elmx_handheld_rect", args)

      "Handheld.Ui.fill" ->
        ui_call("elmx_handheld_fill", args)

      "Handheld.Ui.circle" ->
        ui_call("elmx_handheld_circle", args)

      "Handheld.Ui.fillCircle" ->
        ui_call("elmx_handheld_fill_circle", args)

      "Handheld.Ui.text" ->
        ui_call("elmx_handheld_text", args)

      "Handheld.Display.metrics" ->
        ui_call("elmx_handheld_display_metrics", args)

      "Handheld.Device.ready" ->
        ui_call("elmx_handheld_device_ready", args)

      "Handheld.Nfc.scan" ->
        ui_call("elmx_handheld_nfc_scan", args)

      "Handheld.Nfc.read" ->
        ui_call("elmx_handheld_nfc_read", args)

      "Handheld.Infrared.send" ->
        ui_call("elmx_handheld_ir_send", args)

      "Handheld.Gpio.write" ->
        ui_call("elmx_handheld_gpio_write", args)

      "Handheld.Gpio.read" ->
        ui_call("elmx_handheld_gpio_read", args)

      "Handheld.Radio.get" ->
        ui_call("elmx_handheld_radio_get", args)

      "Handheld.Usb.tap" ->
        ui_call("elmx_handheld_usb_tap", args)

      "Handheld.Usb.code" ->
        {:ok, List.first(args) || %{op: :int_literal, value: 0}}

      "Handheld.Vibes.cancel" ->
        ui_call("elmx_handheld_vibes_cancel", args)

      "Handheld.Vibes.shortPulse" ->
        ui_call("elmx_handheld_vibes_short", args)

      "Handheld.Vibes.longPulse" ->
        ui_call("elmx_handheld_vibes_long", args)

      "Handheld.Vibes.doublePulse" ->
        ui_call("elmx_handheld_vibes_double", args)

      "Handheld.Battery.level" ->
        ui_call("elmx_handheld_battery_level", args)

      "Handheld.Input.presses" ->
        ui_call("elmx_handheld_presses", args)

      "Handheld.Input.onPress" ->
        ui_call("elmx_handheld_on_press", args)

      "Handheld.Input.taps" ->
        ui_call("elmx_handheld_taps", args)

      "Handheld.Nfc.onTag" ->
        ui_call("elmx_handheld_on_tag", args)

      _ ->
        :unmatched
    end
  end
end
