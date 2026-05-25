defmodule Ide.Debugger.Types.WatchProfile do
  @moduledoc """
  Watch hardware profile from `Ide.WatchModels` / `Debugger.watch_profiles/0`.
  """

  alias Ide.Debugger.Types
  @type screen :: %{
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer(),
          optional(String.t()) => Types.wire_input()
        }

  @type profile :: %{
          optional(:name) => String.t(),
          optional(:shape) => String.t(),
          optional(:screen) => screen() | map(),
          optional(:color_mode) => String.t(),
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @type list_item :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:name) => String.t(),
          optional(:shape) => String.t(),
          optional(:screen) => screen() | map(),
          optional(:color_mode) => String.t(),
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_profile :: profile() | map()
  @type wire_list_item :: list_item() | map()
end
