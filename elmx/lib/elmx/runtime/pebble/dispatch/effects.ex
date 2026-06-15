defmodule Elmx.Runtime.Pebble.Dispatch.Effects do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Types

  @spec events_batch(Types.registry_args()) :: Types.wire_cmd()
  def events_batch(_), do: Cmd.none()

  @spec light_enable(Types.registry_args()) :: Types.wire_cmd()
  def light_enable(_), do: Cmd.effect("light", variant: "enable")

  @spec light_disable(Types.registry_args()) :: Types.wire_cmd()
  def light_disable(_), do: Cmd.effect("light", variant: "disable")

  @spec light_interaction(Types.registry_args()) :: Types.wire_cmd()
  def light_interaction(_), do: Cmd.effect("light", variant: "interaction")

  @spec platform_application(Types.registry_args()) :: Types.wire_cmd()
  def platform_application(_), do: Cmd.effect("platform", variant: "application")

  @spec platform_watchface(Types.registry_args()) :: Types.wire_cmd()
  def platform_watchface(_), do: Cmd.effect("platform", variant: "watchface")

  @spec vibes_short_pulse(Types.registry_args()) :: Types.wire_cmd()
  def vibes_short_pulse(_), do: Cmd.effect("vibes", variant: "short_pulse")

  @spec vibes_long_pulse(Types.registry_args()) :: Types.wire_cmd()
  def vibes_long_pulse(_), do: Cmd.effect("vibes", variant: "long_pulse")

  @spec vibes_double_pulse(Types.registry_args()) :: Types.wire_cmd()
  def vibes_double_pulse(_), do: Cmd.effect("vibes", variant: "double_pulse")

  @spec vibes_pattern_cmd(Types.registry_args()) :: Types.wire_cmd()
  def vibes_pattern_cmd(args), do: Cmd.effect("vibes", variant: "pattern", pattern: List.first(args))

  @spec vibes_cancel(Types.registry_args()) :: Types.wire_cmd()
  def vibes_cancel(_), do: Cmd.effect("vibes", variant: "cancel")

  @spec dictation_start(Types.registry_args()) :: Types.wire_cmd()
  def dictation_start(_), do: Cmd.dictation_start()

  @spec dictation_stop(Types.registry_args()) :: Types.wire_cmd()
  def dictation_stop(_), do: Cmd.dictation_stop()

  @spec backlight_cmd(Types.registry_args()) :: Types.wire_cmd()
  def backlight_cmd([maybe]), do: Cmd.backlight_from_maybe(maybe)
  def backlight_cmd(_), do: Cmd.backlight_from_maybe(:Nothing)

  @spec frame_every_cmd(Types.registry_args()) :: Types.wire_cmd()
  def frame_every_cmd([ms, callback]) when is_integer(ms) do
    Cmd.subscription_register("Pebble.Frame.every", interval_ms: ms, callback: callback)
  end

  def frame_every_cmd([ms | rest]) when is_integer(ms) do
    frame_every_cmd([ms, List.first(rest)])
  end

  def frame_every_cmd(_), do: Cmd.subscription_register("Pebble.Frame.every", interval_ms: 33)

  @spec unobstructed_current_bounds_cmd(Types.registry_args()) :: Types.wire_cmd()
  def unobstructed_current_bounds_cmd(args) when is_list(args) do
    Cmd.unobstructed_bounds_peek(List.last(args))
  end

  def unobstructed_current_bounds_cmd(_), do: Cmd.none()

  @spec compass_peek_cmd(Types.registry_args()) :: Types.wire_cmd()
  def compass_peek_cmd(args) when is_list(args), do: Cmd.compass_peek(List.last(args))
end
