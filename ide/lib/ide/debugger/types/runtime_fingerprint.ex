defmodule Ide.Debugger.Types.RuntimeFingerprint do
  @moduledoc false

  alias Ide.Debugger.Types

  @type runtime_fingerprint_atom :: %{
          optional(:runtime_mode) => String.t() | nil,
          optional(:engine) => String.t() | nil,
          optional(:execution_backend) => String.t() | nil,
          optional(:external_fallback_reason) => String.t() | nil,
          optional(:runtime_model_source) => String.t() | nil,
          optional(:view_tree_source) => String.t() | nil,
          optional(:runtime_model_entry_count) => non_neg_integer() | nil,
          optional(:view_tree_node_count) => non_neg_integer() | nil,
          optional(:target_numeric_key) => String.t() | nil,
          optional(:target_numeric_key_source) => String.t() | nil,
          optional(:target_boolean_key) => String.t() | nil,
          optional(:target_boolean_key_source) => String.t() | nil,
          optional(:active_target_key) => String.t() | nil,
          optional(:active_target_key_source) => String.t() | nil,
          optional(:protocol_inbound_count) => non_neg_integer() | nil,
          optional(:protocol_message_count) => non_neg_integer() | nil,
          optional(:protocol_last_inbound_message) => Types.wire_input() | nil,
          optional(:runtime_model_sha256) => String.t() | nil,
          optional(:view_tree_sha256) => String.t() | nil
        }

  @typedoc """
  Trace-export runtime fingerprint (`runtime_model_sha256`, `view_tree_sha256`,
  `execution_backend`, `active_target_key`, protocol counts, etc.).
  """
  @type runtime_fingerprint_wire :: %{
          optional(String.t()) => Types.wire_scalar() | Types.wire_input() | nil
        }

  @type runtime_fingerprint :: runtime_fingerprint_atom() | runtime_fingerprint_wire()

  @type fingerprint_compare_surface_row_atom :: %{
          optional(:changed) => boolean(),
          optional(:backend_changed) => boolean(),
          optional(:key_target_changed) => boolean(),
          optional(:current_model_sha) => String.t() | nil,
          optional(:compare_model_sha) => String.t() | nil,
          optional(:current_view_sha) => String.t() | nil,
          optional(:compare_view_sha) => String.t() | nil,
          optional(:current_execution_backend) => String.t() | nil,
          optional(:compare_execution_backend) => String.t() | nil,
          optional(:current_external_fallback_reason) => String.t() | nil,
          optional(:compare_external_fallback_reason) => String.t() | nil,
          optional(:current_target_numeric_key) => String.t() | nil,
          optional(:compare_target_numeric_key) => String.t() | nil,
          optional(:current_target_numeric_key_source) => String.t() | nil,
          optional(:compare_target_numeric_key_source) => String.t() | nil,
          optional(:current_target_boolean_key) => String.t() | nil,
          optional(:compare_target_boolean_key) => String.t() | nil,
          optional(:current_target_boolean_key_source) => String.t() | nil,
          optional(:compare_target_boolean_key_source) => String.t() | nil,
          optional(:current_active_target_key) => String.t() | nil,
          optional(:compare_active_target_key) => String.t() | nil,
          optional(:current_active_target_key_source) => String.t() | nil,
          optional(:compare_active_target_key_source) => String.t() | nil
        }

  @typedoc """
  Trace-export per-surface compare row (`changed`, `current_model_sha`,
  `baseline_execution_backend`, etc.).
  """
  @type fingerprint_compare_surface_row_wire :: %{
          optional(String.t()) => Types.wire_scalar() | boolean() | nil
        }

  @type fingerprint_compare_surface_row ::
          fingerprint_compare_surface_row_atom() | fingerprint_compare_surface_row_wire()

  @type fingerprint_compare_surfaces_atom :: %{
          optional(:watch) => fingerprint_compare_surface_row_atom(),
          optional(:companion) => fingerprint_compare_surface_row_atom(),
          optional(:phone) => fingerprint_compare_surface_row_atom()
        }

  @type fingerprint_compare_surfaces_wire :: %{
          optional(String.t()) => fingerprint_compare_surface_row_wire()
        }

  @type fingerprint_compare_atom_result :: %{
          optional(:cursor_seq) => integer() | nil,
          optional(:compare_cursor_seq) => integer() | nil,
          optional(:changed_surface_count) => non_neg_integer(),
          optional(:backend_changed_surface_count) => non_neg_integer(),
          optional(:key_target_changed_surface_count) => non_neg_integer(),
          optional(:drift_detail) => String.t() | nil,
          optional(:key_target_drift_detail) => String.t() | nil,
          optional(:surfaces) => fingerprint_compare_surfaces_atom()
        }

  @typedoc """
  Trace-export fingerprint compare (`current_cursor_seq`, `surfaces`, `drift_detail`, etc.).
  """
  @type fingerprint_compare_wire_result :: %{
          optional(String.t()) =>
            Types.wire_scalar()
            | boolean()
            | integer()
            | fingerprint_compare_surfaces_wire()
            | nil
        }

  @type fingerprint_compare_result ::
          fingerprint_compare_atom_result() | fingerprint_compare_wire_result()

  @type surface_fingerprints :: %{
          optional(:watch) => runtime_fingerprint() | nil,
          optional(:companion) => runtime_fingerprint() | nil,
          optional(:phone) => runtime_fingerprint() | nil
        }

  @type digest_surfaces :: %{
          optional(:watch) => runtime_fingerprint_atom(),
          optional(:companion) => runtime_fingerprint_atom(),
          optional(:phone) => runtime_fingerprint_atom()
        }

  @type mcp_compare_surface_row :: %{
          optional(:changed) => boolean(),
          optional(:backend_changed) => boolean(),
          optional(:key_target_changed) => boolean(),
          optional(:current) => runtime_fingerprint_atom() | nil,
          optional(:compare) => runtime_fingerprint_atom() | nil
        }

  @type mcp_compare_surfaces :: %{
          optional(:watch) => mcp_compare_surface_row(),
          optional(:companion) => mcp_compare_surface_row(),
          optional(:phone) => mcp_compare_surface_row()
        }

  @type mcp_compare_result :: %{
          optional(:cursor_seq) => integer(),
          optional(:compare_cursor_seq) => integer(),
          optional(:backend_changed_surface_count) => non_neg_integer(),
          optional(:key_target_changed_surface_count) => non_neg_integer(),
          optional(:backend_drift_detail) => String.t() | nil,
          optional(:key_target_drift_detail) => String.t() | nil,
          optional(:drift_detail) => String.t() | nil,
          optional(:surfaces) => mcp_compare_surfaces()
        }
end
