defmodule Elmx.Runtime.Pebble.Handheld do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Cmd.Wire
  alias Elmx.Runtime.Pebble.Ui

  @buttons ["A", "B", "Up", "Down", "Left", "Right", "Select", "Back"]

  @spec color_rgb(term(), term(), term()) :: integer()
  def color_rgb(r, g, b) do
    red = Bitwise.bsr(clamp(int(r)), 3)
    green = Bitwise.bsr(clamp(int(g)), 2)
    blue = Bitwise.bsr(clamp(int(b)), 3)
    Bitwise.bor(Bitwise.bsl(red, 11), Bitwise.bor(Bitwise.bsl(green, 5), blue))
  end

  @spec clear(term()) :: map()
  def clear(color), do: Ui.clear(color)

  @spec pixel(term(), term()) :: map()
  def pixel(point, color), do: Ui.pixel(point_map(point), color)

  @spec line(term(), term(), term()) :: map()
  def line(from, to, color), do: Ui.line(point_map(from), point_map(to), color)

  @spec rect(term(), term()) :: map()
  def rect(bounds, color), do: Ui.rect(bounds_map(bounds), color)

  @spec fill(term(), term()) :: map()
  def fill(bounds, color), do: Ui.fill_rect(bounds_map(bounds), color)

  @spec circle(term(), term(), term()) :: map()
  def circle(center, radius, color), do: Ui.circle(point_map(center), radius, color)

  @spec fill_circle(term(), term(), term()) :: map()
  def fill_circle(center, radius, color), do: Ui.fill_circle(point_map(center), radius, color)

  @spec text(term(), term(), term()) :: map()
  def text(point, string, color) do
    {x, y} = point_xy(point)

    %{
      type: "text",
      label: to_string(string),
      text: to_string(string),
      x: x,
      y: y,
      position: %{x: x, y: y},
      bounds: %{x: x, y: y, w: 0, h: 0},
      color: color
    }
  end

  @spec effect(String.t(), list()) :: map()
  def effect(name, args \\ []) when is_binary(name) do
    Cmd.effect("handheld", variant: name, extra: %{"args" => args})
  end

  def display_metrics(callback) do
    Cmd.task_immediate(apply_msg(callback, %{"colorDepth" => 16, "height" => 240, "width" => 320}))
  end

  def device_ready(_module, callback), do: Cmd.task_immediate(apply_msg(callback, true))
  def nfc_scan, do: effect("nfc.scan")
  def nfc_read, do: effect("nfc.read")
  def ir_send(count), do: effect("ir.send", [count])
  def gpio_write(pin, level), do: effect("gpio.write", [pin, level_bit(level)])
  def gpio_read(_pin, callback), do: Cmd.task_immediate(apply_msg(callback, :High))
  def radio_get(url), do: effect("radio.get", [url])
  def usb_tap(key), do: effect("usb.tap", [key_code(key)])
  def vibes_cancel, do: effect("vibes.cancel")
  def vibes_short, do: effect("vibes.short")
  def vibes_long, do: effect("vibes.long")
  def vibes_double, do: effect("vibes.double")
  def battery_level(callback), do: Cmd.task_immediate(apply_msg(callback, 80))

  @spec presses(term()) :: [map()]
  def presses(to_msg) when is_function(to_msg, 1) do
    Enum.map(@buttons, fn button ->
      register("Handheld.Input.presses", button, to_msg.(String.to_atom(button)))
    end)
  end

  def presses(_to_msg), do: []

  @spec on_press(term(), term()) :: map()
  def on_press(button, msg), do: register("Handheld.Input.onPress", button_name(button), msg)

  @spec taps(term()) :: map()
  def taps(to_msg) do
    register("Handheld.Input.taps", "taps", apply_msg(to_msg, %{"x" => 8, "y" => 8}))
  end

  @spec on_tag(term()) :: map()
  def on_tag(to_msg) do
    register("Handheld.Nfc.onTag", "ontag", apply_msg(to_msg, "04A1B2"))
  end

  defp register(target, event_kind, msg) do
    {message, message_value} = Wire.message_wire(msg)

    %{
      "kind" => "cmd.subscription.register",
      "package" => "elm-pebble/elm-watch",
      "target" => target,
      "event_kind" => event_kind,
      "message" => message,
      "message_value" => message_value
    }
  end

  defp apply_msg(callback, value) when is_function(callback, 1), do: callback.(value)
  defp apply_msg(callback, _value), do: callback

  defp button_name(name) when is_atom(name), do: Atom.to_string(name)
  defp button_name(name) when is_binary(name), do: name
  defp button_name(_name), do: "Select"

  defp point_map(point) do
    {x, y} = point_xy(point)
    %{x: x, y: y}
  end

  defp bounds_map(bounds) do
    %{
      x: field(bounds, ["x", :x]),
      y: field(bounds, ["y", :y]),
      w: field(bounds, ["width", :width, "w", :w]),
      h: field(bounds, ["height", :height, "h", :h])
    }
  end

  defp point_xy(point) do
    {field(point, ["x", :x]), field(point, ["y", :y])}
  end

  defp field(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:ok, value}
        :error -> nil
      end
    end)
    |> case do
      {:ok, value} -> value
      _ -> 0
    end
  end

  defp field(_map, _keys), do: 0

  defp level_bit(:High), do: 1
  defp level_bit(:Low), do: 0
  defp level_bit("High"), do: 1
  defp level_bit("Low"), do: 0
  defp level_bit(bit) when is_integer(bit), do: bit
  defp level_bit(other), do: other

  defp key_code(code) when is_integer(code), do: code
  defp key_code(other), do: other

  defp int(value) when is_integer(value), do: value
  defp int(value) when is_binary(value), do: String.to_integer(value)
  defp int(_value), do: 0

  defp clamp(n) when is_integer(n), do: n |> max(0) |> min(255)
end
