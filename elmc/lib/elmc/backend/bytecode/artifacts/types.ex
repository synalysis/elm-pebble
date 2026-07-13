defmodule Elmc.Backend.Bytecode.Artifacts.Types do
  @moduledoc false

  @type function_row :: %{
          required(:module) => String.t(),
          required(:name) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:params) => [String.t()]
        }

  @type skipped_row :: %{
          optional(:module) => String.t() | nil,
          optional(:name) => String.t() | nil,
          optional(:reason) => atom() | String.t() | nil
        }

  @type coverage_stat :: integer() | float() | boolean() | String.t() | nil

  @type coverage_bucket :: %{
          optional(String.t()) => coverage_stat() | coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type plan_coverage :: %{
          optional(String.t()) => coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type plan_toolchain :: %{
          optional(:mode) => :off | :shadow | :primary | String.t(),
          optional(:strict) => boolean(),
          optional(String.t()) => coverage_stat(),
          optional(atom()) => coverage_stat()
        }

  @type summary_available :: %{
          required(:available) => true,
          optional(:contract) => String.t() | nil,
          optional(:version) => String.t() | nil,
          optional(:manifest_path) => String.t(),
          optional(:function_count) => non_neg_integer(),
          optional(:skipped_count) => non_neg_integer(),
          optional(:pruned_count) => non_neg_integer(),
          optional(:plan_toolchain) => plan_toolchain() | nil,
          optional(:plan_coverage) => plan_coverage() | nil,
          optional(:functions) => [function_row()],
          optional(:skipped) => [skipped_row()]
        }

  @type summary_unavailable :: %{
          required(:available) => false,
          optional(:reason) => String.t()
        }

  @type summary :: summary_available() | summary_unavailable()

  @type manifest_scalar :: String.t() | integer() | boolean() | nil

  @type manifest_value ::
          manifest_scalar()
          | [manifest_value()]
          | %{optional(String.t()) => manifest_value()}

  @type manifest_function_entry :: %{optional(String.t()) => manifest_value()}

  @type wire_manifest :: %{optional(String.t()) => manifest_value()}

  @type bytecode_io_error :: Elmc.Types.file_error() | Jason.DecodeError.t()

  @type bytecode_load_error ::
          bytecode_io_error()
          | :missing_manifest_entry
          | :invalid_manifest
end
