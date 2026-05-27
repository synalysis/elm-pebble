defmodule Ide.Debugger.Types.WatchProfile do
  @moduledoc """
  Watch hardware profile from `Ide.WatchModels` / `Debugger.watch_profiles/0`.
  """

  alias Ide.WatchModels.Profile, as: CatalogProfile

  @type screen :: CatalogProfile.screen()
  @type profile :: CatalogProfile.t()
  @type wire_profile :: CatalogProfile.wire()

  @type list_item :: %{
          optional(:id) => String.t(),
          optional(:label) => String.t(),
          optional(:name) => String.t(),
          optional(:shape) => CatalogProfile.shape(),
          optional(:screen) => screen() | map(),
          optional(:color_mode) => CatalogProfile.color_mode(),
          optional(:has_microphone) => boolean(),
          optional(:has_compass) => boolean(),
          optional(:supports_health) => boolean(),
          optional(String.t()) => term()
        }

  @type wire_list_item :: list_item() | map()
end
