defmodule Ide.Resources.Types do
  @moduledoc """
  Shared types for project resource manifests and generated Elm modules.
  """

  alias Ide.Resources.ResourceStore

  @type bitmap_entry :: ResourceStore.bitmap_entry()
  @type font_entry :: ResourceStore.font_entry()
  @type font_source :: ResourceStore.font_source()
  @type vector_entry :: ResourceStore.vector_entry()

  @type manifest_entry :: bitmap_entry() | font_entry() | vector_entry()
  @type manifest :: %{
          optional(String.t()) => wire_input(),
          optional(:schema_version) => integer(),
          optional(:entries) => [manifest_entry()]
        }

  @type workspace_path :: String.t()

  @type wire_input :: String.t() | integer() | boolean() | list() | map() | nil

  @type font_lookup_error :: :font_source_not_found

  @type asset_type_error ::
          :unsupported_bitmap_type
          | :unsupported_font_type
          | :unsupported_vector_type
          | :invalid_font_height
          | :svg_conversion_failed
          | :invalid_pdc_output

  @type asset_lookup_error ::
          :bitmap_not_found
          | :font_not_found
          | :font_variant_not_found
          | :vector_not_found
          | font_lookup_error()

  @type manifest_io_error :: File.posix() | Jason.EncodeError.t()

  @type resource_error ::
          manifest_io_error() | asset_lookup_error() | asset_type_error()
end
