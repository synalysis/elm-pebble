defmodule Elmc.TestSupport.Types do
  @moduledoc false

  alias Elmc.CLI.Types, as: ElmcCliTypes
  alias Elmc.Types
  alias Elmx.Types, as: ElmxTypes

  @type compile_opts :: Types.compile_options()

  @type timeout_error :: :timeout

  @type corpus_compile_probe_error ::
          ElmcCliTypes.compile_error() | ElmxTypes.compile_error() | timeout_error()

  @type corpus_execution_error ::
          ElmcCliTypes.compile_error()
          | ElmxTypes.compile_error()
          | timeout_error()
          | String.t()
          | {atom(), term()}
          | atom()
          | %{optional(String.t()) => String.t() | integer() | boolean() | nil}

  @type corpus_metadata_row :: %{optional(String.t()) => String.t()}

  @type corpus_metadata_index :: %{String.t() => corpus_metadata_row()}

  @type corpus_index :: %{
          optional(String.t()) => String.t() | integer() | boolean() | list() | nil,
          optional(atom()) => String.t() | integer() | boolean() | list() | nil
        }

  @type corpus_scorecard :: corpus_index()

  @type rc_registry_entry :: %{
          required(:fixture) => String.t(),
          required(:probes) => [String.t()],
          optional(atom()) => String.t() | integer() | boolean() | nil
        }

  @type rc_registry :: %{optional(String.t()) => rc_registry_entry()}

  @type rc_probe_exceptions :: %{optional(String.t()) => String.t() | integer() | boolean() | nil}
end
