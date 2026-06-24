defmodule Ide.Resources.Types do
  @moduledoc """
  Shared types for project resource manifests and generated Elm modules.
  """

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias Ide.Resources.ConversionReport

  @type vector_import_report :: ConversionReport.t() | ConversionReport.wire()

  @type bitmap_variant_entry :: %{
          filename: String.t(),
          mime: String.t(),
          bytes: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @type bitmap_entry :: %{
          required(:id) => String.t(),
          required(:ctor) => String.t(),
          required(:base_name) => String.t(),
          required(:filename) => String.t() | nil,
          required(:mime) => String.t() | nil,
          required(:bytes) => non_neg_integer(),
          required(:width) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:variants) => %{optional(String.t()) => bitmap_variant_entry()},
          optional(:resource_id) => pos_integer(),
          optional(:ctor_prefix) => String.t(),
          optional(:variant_slots) => [bitmap_variant_slot()],
          optional(:legacy_preview_data_url) => String.t() | nil,
          optional(:has_legacy) => boolean()
        }

  @type bitmap_variant_slot :: %{
          required(:color_mode) => String.t(),
          required(:label) => String.t(),
          required(:platforms) => String.t(),
          required(:preview_data_url) => String.t() | nil,
          required(:preview_skipped) => boolean(),
          optional(:filename) => String.t() | nil,
          optional(:bytes) => non_neg_integer() | nil
        }

  @type font_entry :: %{
          required(:id) => String.t(),
          required(:ctor) => String.t(),
          required(:source_id) => String.t(),
          required(:filename) => String.t(),
          required(:mime) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:characters) => String.t(),
          required(:tracking_adjust) => integer(),
          required(:compatibility) => String.t(),
          required(:target_platforms) => [String.t()],
          optional(:resource_id) => pos_integer()
        }

  @type font_source :: %{
          required(:id) => String.t(),
          required(:filename) => String.t(),
          required(:mime) => String.t(),
          required(:bytes) => non_neg_integer(),
          optional(:resource_id) => pos_integer()
        }

  @type vector_entry :: %{
          required(:id) => String.t(),
          required(:ctor) => String.t(),
          required(:base_name) => String.t(),
          required(:filename) => String.t(),
          required(:mime) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:source) => String.t(),
          required(:kind) => String.t(),
          required(:frames) => non_neg_integer() | nil,
          required(:frame_duration_ms) => non_neg_integer() | nil,
          optional(:resource_id) => pos_integer(),
          optional(:ctor_prefix) => String.t(),
          optional(:kind_label) => String.t(),
          optional(:preview_svg) => String.t() | nil,
          optional(:sequence_label) => String.t() | nil
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

  @type animation_resource_entry :: %{
          required(:id) => String.t(),
          required(:ctor) => String.t(),
          required(:base_name) => String.t(),
          required(:filename) => String.t(),
          required(:mime) => String.t(),
          required(:bytes) => non_neg_integer(),
          required(:width) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:frame_count) => non_neg_integer(),
          required(:duration_ms) => non_neg_integer(),
          required(:play_count) => non_neg_integer() | :infinite,
          optional(:resource_id) => pos_integer(),
          optional(:ctor_prefix) => String.t(),
          optional(:preview_data_url) => String.t() | nil,
          optional(:loop_label) => String.t() | nil
        }

  @type speaker_sample_import_ok :: %{
          optional(:entry) => manifest_wire_row(),
          optional(:entries) => [manifest_wire_row()],
          optional(:duplicate) => boolean()
        }

  @type manifest_entry ::
          bitmap_entry() | font_entry() | font_source() | vector_entry() | animation_entry()

  @type manifest_wire_row :: %{
          optional(String.t()) => wire_input(),
          optional(atom()) => wire_input()
        }

  @type manifest :: %{
          optional(String.t()) => wire_input(),
          optional(:schema_version) => integer(),
          optional(:entries) => [manifest_entry()]
        }

  @type workspace_path :: String.t()

  @type wire_input :: DebuggerTypes.wire_input()

  @type font_lookup_error :: :font_source_not_found

  @type asset_type_error ::
          :unsupported_bitmap_type
          | :invalid_bitmap_image
          | :bitmap_converter_missing
          | :bitmap_conversion_failed
          | :unsupported_font_type
          | :unsupported_vector_type
          | :invalid_font_height
          | :svg_conversion_failed
          | :invalid_pdc_output
          | :unsupported_speaker_sample_type
          | :invalid_speaker_sample
          | :speaker_sample_too_large
          | :speaker_sample_total_too_large

  @type asset_lookup_error ::
          :bitmap_not_found
          | :font_not_found
          | :font_variant_not_found
          | :vector_not_found
          | font_lookup_error()

  @type manifest_io_error :: File.posix() | Jason.EncodeError.t()

  @type resource_error ::
          manifest_io_error() | asset_lookup_error() | asset_type_error()

  @type import_duplicate :: %{duplicate: true, entry: manifest_wire_row()}
  @type import_source_duplicate :: %{duplicate: true, source: manifest_wire_row()}

  @type manifest_entries_update :: %{
          entry: manifest_wire_row(),
          entries: [manifest_wire_row()]
        }

  @type bitmap_import_result ::
          {:ok, manifest_entries_update() | import_duplicate()} | {:error, resource_error()}

  @type bitmap_directory_import_stats :: %{
          imported: non_neg_integer(),
          skipped: non_neg_integer(),
          duplicates: non_neg_integer()
        }

  @type font_import_ok :: %{source: manifest_wire_row(), entries: [manifest_wire_row()]}
  @type font_import_result ::
          {:ok, font_import_ok() | import_source_duplicate()} | {:error, resource_error()}

  @type font_variant_result ::
          {:ok, manifest_entries_update()} | {:error, resource_error()}

  @type font_manifest_payload :: %{
          optional(String.t()) => wire_input(),
          optional(atom()) => wire_input()
        }

  @type font_delete_source_ok :: %{
          sources: [manifest_wire_row()],
          entries: [manifest_wire_row()]
        }

  @type font_delete_source_result ::
          {:ok, font_delete_source_ok()} | {:error, resource_error()}

  @type font_form_params :: %{
          optional(String.t()) => wire_input(),
          optional(atom()) => wire_input()
        }

  @type vector_import_wire_ok :: %{
          required(:entry) => manifest_wire_row(),
          required(:entries) => [manifest_wire_row()],
          optional(:preview_svg) => String.t() | nil,
          optional(:report) => vector_import_report() | nil
        }

  @type vector_import_result ::
          {:ok, vector_import_wire_ok() | import_duplicate()} | {:error, resource_error()}

  @type vector_import_extras :: %{
          optional(:kind) => String.t(),
          optional(:preview_svg) => String.t() | nil,
          optional(:report) => vector_import_report() | nil,
          optional(:frames) => non_neg_integer(),
          optional(:frame_duration_ms) => non_neg_integer()
        }

  @type delete_entries_result :: {:ok, [manifest_wire_row()]} | {:error, resource_error()}
  @type rename_result :: {:ok, manifest_entries_update()} | {:error, resource_error()}

  @type animation_import_result ::
          {:ok, manifest_entries_update() | import_duplicate()} | {:error, resource_error()}

  @type speaker_sample_entry :: manifest_wire_row()
end
