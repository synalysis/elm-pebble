defmodule Ide.Debugger.SurfaceTargets do
  @moduledoc false

  alias Ide.Debugger.Types

  @spec normalize(Types.surface_label_input()) :: Types.surface_target()
  def normalize("companion"), do: :companion
  def normalize("protocol"), do: :companion
  def normalize("phone"), do: :companion
  def normalize(:companion), do: :companion
  def normalize(:phone), do: :companion
  def normalize(_), do: :watch

  @spec normalize_optional(Types.wire_input()) :: Types.surface_target() | nil
  def normalize_optional(nil), do: nil
  def normalize_optional(""), do: nil
  def normalize_optional(value), do: normalize(value)

  @spec source_root(Types.surface_target()) :: String.t()
  def source_root(:watch), do: "watch"
  def source_root(:companion), do: "phone"
  def source_root(:phone), do: "phone"

  @spec replay_label(Types.surface_target() | nil) :: String.t()
  def replay_label(nil), do: "all"
  def replay_label(target), do: source_root(target)

  @spec tick_targets(Types.surface_target() | nil) :: [Types.surface_target()]
  def tick_targets(nil), do: [:watch, :companion, :phone]
  def tick_targets(target) when target in [:watch, :companion, :phone], do: [target]

  @spec normalize_source_root(map()) :: String.t()
  def normalize_source_root(attrs) when is_map(attrs) do
    case Map.get(attrs, :source_root) || Map.get(attrs, "source_root") do
      "protocol" -> "protocol"
      "phone" -> "phone"
      _ -> "watch"
    end
  end
end

