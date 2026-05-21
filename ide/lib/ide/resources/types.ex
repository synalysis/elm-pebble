defmodule Ide.Resources.Types do
  @moduledoc """
  Shared types for project resource manifests and generated Elm modules.
  """

  alias Ide.Resources.ResourceStore

  @type bitmap_entry :: ResourceStore.bitmap_entry()
  @type font_entry :: ResourceStore.font_entry()
  @type font_source :: ResourceStore.font_source()

  @type manifest_entry :: map()
  @type manifest :: %{
          optional(String.t()) => term(),
          optional(:schema_version) => integer(),
          optional(:entries) => [manifest_entry()]
        }

  @type workspace_path :: String.t()

  @type wire_input :: String.t() | integer() | boolean() | list() | map() | nil

  @type font_lookup_error :: :font_source_not_found

  @type asset_lookup_error ::
          :bitmap_not_found | :font_not_found | :font_variant_not_found | font_lookup_error()

  @type asset_type_error ::
          :unsupported_bitmap_type | :unsupported_font_type | :invalid_font_height

  @type manifest_io_error :: File.posix() | Jason.EncodeError.t()

  @type resource_error ::
          manifest_io_error() | asset_lookup_error() | asset_type_error()
end
