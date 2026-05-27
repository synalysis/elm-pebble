defmodule Ide.WatchModels.Profile do
  @moduledoc """
  Types for hardware catalog entries in `Ide.WatchModels`.

  Runtime maps use string keys (`"screen"`, `"width"`, …) as returned by
  `profile_for/1`. Typespecs use optional atom keys for Dialyzer and allow
  `wire/1` for JSON-shaped maps.
  """

  @type shape :: String.t()
  @type color_mode :: String.t()

  @type screen :: %{
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer(),
          optional(String.t()) => term()
        }

  @type t :: %{
          optional(:name) => String.t(),
          optional(:shape) => shape(),
          optional(:screen) => screen() | map(),
          optional(:color_mode) => color_mode(),
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(String.t()) => term()
        }

  @type wire_screen :: screen() | %{String.t() => term()}
  @type wire :: t() | %{String.t() => term()}
end
