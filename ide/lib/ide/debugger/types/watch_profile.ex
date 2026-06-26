defmodule Ide.Debugger.Types.WatchProfile do
  @moduledoc """
  Watch hardware profile from `Ide.WatchModels` / `Debugger.watch_profiles/0`.
  """

  alias Ide.Debugger.Types
  alias Ide.WatchModels.Profile, as: CatalogProfile

  @type screen :: CatalogProfile.screen()
  @type wire_screen :: CatalogProfile.wire_screen()
  @type profile :: CatalogProfile.t()
  @type wire_profile :: CatalogProfile.wire()

  @type list_item :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:name) => String.t(),
          optional(:shape) => CatalogProfile.shape(),
          optional(:screen) => screen() | wire_screen(),
          optional(:color_mode) => CatalogProfile.color_mode(),
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "Wire JSON list item when atom-key `list_item/0` is unavailable."
  @type wire_list_item :: list_item() | wire_profile()
end
