defmodule Ide.Resources.Types do
  @moduledoc """
  Shared types for project resource manifests and generated Elm modules.
  """

  @type bitmap_variant_entry :: %{
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @type bitmap_entry :: %{
          id: String.t(),
          ctor: String.t(),
          base_name: String.t(),
          filename: String.t() | nil,
          mime: String.t() | nil,
          bytes: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer(),
          variants: %{optional(String.t()) => bitmap_variant_entry()}
        }

  @type font_entry :: %{
          id: String.t(),
          ctor: String.t(),
          source_id: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          height: non_neg_integer(),
          characters: String.t(),
          tracking_adjust: integer(),
          compatibility: String.t(),
          target_platforms: [String.t()]
        }

  @type font_source :: %{
          id: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer()
        }

  @type vector_entry :: %{
          id: String.t(),
          ctor: String.t(),
          base_name: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          source: String.t(),
          kind: String.t(),
          frames: non_neg_integer() | nil,
          frame_duration_ms: non_neg_integer() | nil
        }

  @type animation_entry :: %{
          id: String.t(),
          ctor: String.t(),
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          frames: non_neg_integer() | nil,
          frame_duration_ms: non_neg_integer() | nil
        }

  @type manifest_entry :: bitmap_entry() | font_entry() | font_source() | vector_entry() | animation_entry()
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
