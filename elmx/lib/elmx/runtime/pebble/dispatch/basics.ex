defmodule Elmx.Runtime.Pebble.Dispatch.Basics do
  @moduledoc false

  alias Elmx.Types

  alias Elmx.Runtime.Core

  @spec list_repeat(Types.registry_args()) :: Types.elm_list()
  def list_repeat([n, value]), do: Core.list_repeat(n, value)
  def list_repeat(_), do: []

  @spec list_cons(Types.registry_args()) :: Types.elm_list()
  def list_cons([head, tail]) when is_list(tail), do: [head | tail]
  def list_cons([head | rest]), do: [head | List.first(rest) || []]
  def list_cons(_), do: []

  @spec to_float(Types.registry_args()) :: float()
  def to_float([value]) when is_float(value), do: value
  def to_float([value]) when is_integer(value), do: value * 1.0
  def to_float([value]) when is_number(value), do: value * 1.0
  def to_float(_), do: 0.0

  @spec floor(Types.registry_args()) :: integer()
  def floor([value]) when is_number(value), do: Kernel.floor(value)
  def floor(_), do: 0

  @spec ceiling(Types.registry_args()) :: integer()
  def ceiling([value]) when is_number(value), do: Kernel.ceil(value)
  def ceiling(_), do: 0

  @spec round_val(Types.registry_args()) :: integer()
  def round_val([value]) when is_number(value), do: Kernel.round(value)
  def round_val(_), do: 0

  @spec truncate(Types.registry_args()) :: integer()
  def truncate([value]) when is_number(value), do: trunc(value)
  def truncate(_), do: 0

  @spec math_clamp(Types.registry_args()) :: number()
  def math_clamp([lo, hi, value]) when is_number(lo) and is_number(hi) and is_number(value),
    do: max(lo, min(hi, value))

  def math_clamp([lo, hi, value]), do: max(lo, min(hi, value))
  def math_clamp(_), do: 0

  @spec rotation_from_pebble_angle(Types.registry_args()) :: number()
  def rotation_from_pebble_angle(args), do: List.first(args) || 0

  @spec kernel_time_now_millis(Types.registry_args()) :: integer()
  def kernel_time_now_millis(_), do: :os.system_time(:millisecond)

  @spec collision_rect_rect(Types.registry_args()) :: boolean()
  def collision_rect_rect([a, b]) when is_map(a) and is_map(b) do
    ax = int_field(a, "x")
    ay = int_field(a, "y")
    aw = int_field(a, "w")
    ah = int_field(a, "h")
    bx = int_field(b, "x")
    by = int_field(b, "y")
    bw = int_field(b, "w")
    bh = int_field(b, "h")

    ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
  end

  def collision_rect_rect(_), do: false

  @spec int_field(Types.wire_map(), String.t()) :: integer()
  defp int_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key)) || 0
  end
end
