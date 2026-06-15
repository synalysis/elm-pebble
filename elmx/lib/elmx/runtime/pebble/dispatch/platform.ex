defmodule Elmx.Runtime.Pebble.Dispatch.Platform do
  @moduledoc false

  alias Elmx.Runtime.LaunchContext
  alias Elmx.Runtime.Pebble.DeviceStubs
  alias Elmx.Types

  @spec launch_reason(Types.registry_args()) :: integer()
  def launch_reason([reason]), do: LaunchContext.launch_reason_to_int(reason)
  def launch_reason(_), do: LaunchContext.launch_reason_to_int(nil)

  @spec display_shape_is_round(Types.registry_args()) :: boolean()
  def display_shape_is_round([shape]), do: display_shape_is_round_value(shape)
  def display_shape_is_round(_), do: false

  @spec display_shape_is_round_value(Types.display_shape_like()) :: boolean()
  def display_shape_is_round_value(%{"ctor" => ctor}) when is_binary(ctor),
    do: String.contains?(ctor, "Round") or String.contains?(ctor, "round")

  def display_shape_is_round_value({ctor, _}) when is_atom(ctor),
    do: ctor in [:Round, :ChinookRound, :EmeryRound]

  def display_shape_is_round_value(_), do: false

  @spec color_capability_is_color(Types.registry_args()) :: boolean()
  def color_capability_is_color([mode]), do: color_capability_is_color_value(mode)
  def color_capability_is_color(_), do: false

  @spec color_capability_is_color_value(Types.color_mode_like()) :: boolean()
  def color_capability_is_color_value(:Color), do: true
  def color_capability_is_color_value("Color"), do: true
  def color_capability_is_color_value(%{"ctor" => "Color"}), do: true
  def color_capability_is_color_value({:Color}), do: true
  def color_capability_is_color_value(_), do: false

  @spec health_device_cmd(String.t(), Types.registry_args()) :: Types.wire_cmd()
  def health_device_cmd(kind, args) when is_binary(kind) and is_list(args) do
    DeviceStubs.device(kind, [List.last(args)])
  end
end
