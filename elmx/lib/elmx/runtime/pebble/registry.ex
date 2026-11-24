defmodule Elmx.Runtime.Pebble.Registry do
  @moduledoc """
  Handler table for `elmx_*` Pebble platform runtime calls.

  Used by `Elmx.Runtime.Generator`, `Pebble.runtime_dispatch/2`, and IDE-stepped apps.
  Several `elmx_core_*` symbols mirror `Intrinsics.Registry` so `Generator.compile_call/2`
  can resolve them without falling through. UI/http/dispatch handlers use `wrap_modules` for
  splat argument lists.
  """
  alias Elmx.Types, as: Types


  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Pebble.Registry.{
    Cmd,
    Companion,
    Core,
    Device,
    Http,
    Json,
    Subscription,
    Task,
    Time,
    Ui
  }
  alias Elmx.Types

  @type handler :: Handler.t()

  @wrap_modules [
    Elmx.Runtime.Pebble.Dispatch,
    Elmx.Runtime.Http
  ]

  @spec handlers() :: %{String.t() => handler()}
  def handlers, do: handlers_map()

  @spec symbols() :: [String.t()]
  def symbols, do: handlers() |> Map.keys() |> Enum.sort()

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name), do: Map.has_key?(handlers(), name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes) when is_binary(name) and is_list(arg_codes) do
    case Map.get(handlers(), name) do
      nil -> :error
      handler -> {:ok, Handler.compile(handler, arg_codes, wrap_modules: @wrap_modules)}
    end
  end

  @spec apply(String.t(), Types.registry_args()) :: Types.runtime_dispatch_result()
  def apply(name, args) when is_binary(name) and is_list(args) do
    case Map.get(handlers(), name) do
      nil ->
        if Dispatch.kernel_runtime_function?(name) do
          Dispatch.kernel_runtime_stub(name, args)
        else
          raise ArgumentError, "unsupported elmx runtime call #{name}"
        end

      handler ->
        Handler.invoke(handler, args, wrap_modules: @wrap_modules)
    end
  end

  defp handheld_handlers do
    alias Elmx.Runtime.Pebble.Handheld

    %{
      "elmx_handheld_color_rgb" => {Handheld, :color_rgb},
      "elmx_handheld_clear" => {Handheld, :clear},
      "elmx_handheld_pixel" => {Handheld, :pixel},
      "elmx_handheld_line" => {Handheld, :line},
      "elmx_handheld_rect" => {Handheld, :rect},
      "elmx_handheld_fill" => {Handheld, :fill},
      "elmx_handheld_circle" => {Handheld, :circle},
      "elmx_handheld_fill_circle" => {Handheld, :fill_circle},
      "elmx_handheld_text" => {Handheld, :text},
      "elmx_handheld_display_metrics" => {Handheld, :display_metrics},
      "elmx_handheld_device_ready" => {Handheld, :device_ready},
      "elmx_handheld_nfc_scan" => {Handheld, :nfc_scan},
      "elmx_handheld_nfc_read" => {Handheld, :nfc_read},
      "elmx_handheld_ir_send" => {Handheld, :ir_send},
      "elmx_handheld_gpio_write" => {Handheld, :gpio_write},
      "elmx_handheld_gpio_read" => {Handheld, :gpio_read},
      "elmx_handheld_radio_get" => {Handheld, :radio_get},
      "elmx_handheld_usb_tap" => {Handheld, :usb_tap},
      "elmx_handheld_vibes_cancel" => {Handheld, :vibes_cancel},
      "elmx_handheld_vibes_short" => {Handheld, :vibes_short},
      "elmx_handheld_vibes_long" => {Handheld, :vibes_long},
      "elmx_handheld_vibes_double" => {Handheld, :vibes_double},
      "elmx_handheld_battery_level" => {Handheld, :battery_level},
      "elmx_handheld_presses" => {Handheld, :presses},
      "elmx_handheld_on_press" => {Handheld, :on_press},
      "elmx_handheld_taps" => {Handheld, :taps},
      "elmx_handheld_on_tag" => {Handheld, :on_tag}
    }
  end

  @spec handlers_map() :: %{String.t() => handler()}
  defp handlers_map do
    %{}
    |> Map.merge(Http.handlers())
    |> Map.merge(Ui.handlers())
    |> Map.merge(Core.handlers())
    |> Map.merge(Task.handlers())
    |> Map.merge(Time.handlers())
    |> Map.merge(Cmd.handlers())
    |> Map.merge(handheld_handlers())
    |> Map.merge(Subscription.handlers())
    |> Map.merge(Device.handlers())
    |> Map.merge(Companion.handlers())
    |> Map.merge(Json.handlers())
  end
end
