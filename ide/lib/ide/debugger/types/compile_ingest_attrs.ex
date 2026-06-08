defmodule Ide.Debugger.Types.CompileIngestAttrs do
  @moduledoc """
  Attributes for `Debugger.ingest_elmc_check/2`, `ingest_elmc_compile/2`, and `ingest_elmc_manifest/2`.
  """

  alias Ide.Debugger.Types

  @type status :: :ok | :error | String.t()

  @type t :: %{
          optional(:status) => status(),
          optional(:compiled_path) => String.t(),
          optional(:checked_path) => String.t(),
          optional(:manifest_path) => String.t(),
          optional(:revision) => String.t(),
          optional(:cached) => boolean(),
          optional(:cached?) => boolean(),
          optional(:strict) => boolean(),
          optional(:strict?) => boolean(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(:detail) => String.t(),
          optional(:source_root) => String.t(),
          optional(:schema_version) => String.t() | integer() | map() | nil,
          optional(:diagnostics) => list(),
          optional(:elmx_manifest) => Types.elmx_manifest(),
          optional(:elmx_revision) => String.t(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()
end
