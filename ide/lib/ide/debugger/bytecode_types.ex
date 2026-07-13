defmodule Ide.Debugger.BytecodeTypes do
  @moduledoc false

  alias Elmc.Backend.Bytecode.Runtime

  @type function_entry :: %{
          optional(String.t()) => Runtime.value() | String.t() | integer() | boolean() | nil
        }

  @type function_row :: %{
          required(:module) => String.t(),
          required(:name) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:params) => [String.t()]
        }

  @type coverage_stat :: integer() | float() | boolean() | String.t() | nil

  @type coverage_bucket :: %{
          optional(String.t()) => coverage_stat() | coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type plan_toolchain :: %{
          optional(:mode) => :off | :shadow | :primary | String.t(),
          optional(:strict) => boolean(),
          optional(String.t()) => coverage_stat(),
          optional(atom()) => coverage_stat()
        }

  @type plan_coverage :: %{
          optional(String.t()) => coverage_bucket(),
          optional(atom()) => coverage_stat()
        }

  @type failed_preview_row :: %{
          optional(String.t()) => String.t()
        }

  @type skipped_function_row :: %{
          optional(String.t()) => String.t() | nil
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
          optional(:skipped) => [skipped_function_row()]
        }

  @type summary_unavailable :: %{
          required(:available) => false,
          optional(:reason) => String.t()
        }

  @type summary :: summary_available() | summary_unavailable()

  @type smoke_param :: Runtime.value()

  @type runtime_value :: Runtime.value()

  @type bytecode_load_error ::
          Elmc.Types.file_error()
          | Jason.DecodeError.t()
          | :missing_manifest_entry
          | :invalid_manifest
end
