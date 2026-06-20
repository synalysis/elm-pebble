defmodule Elmc.Backend.CCodegen.PlatformStatic do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @display_shape_targets MapSet.new([
    "Pebble.Platform.displayShapeIsRound",
    "Platform.displayShapeIsRound"
  ])

  @color_capability_targets MapSet.new([
    "Pebble.Platform.colorCapabilityIsColor",
    "Platform.colorCapabilityIsColor"
  ])

  @spec platform_static_macro(Types.ir_expr()) :: String.t() | nil
  def platform_static_macro(%{platform_static_macro: macro}) when is_binary(macro), do: macro

  def platform_static_macro(%{op: :qualified_call, target: target}) when is_binary(target) do
    cond do
      MapSet.member?(@display_shape_targets, target) -> "PBL_ROUND"
      MapSet.member?(@color_capability_targets, target) -> "PBL_COLOR"
      true -> nil
    end
  end

  def platform_static_macro(_expr), do: nil

  @spec platform_static?(Types.ir_expr()) :: boolean()
  def platform_static?(expr), do: platform_static_macro(expr) != nil
end
