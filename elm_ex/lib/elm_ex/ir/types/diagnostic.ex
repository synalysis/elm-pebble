defmodule ElmEx.IR.Types.Diagnostic do
  @moduledoc """
  Diagnostics attached to `ElmEx.IR.t()` from lowering and validation.

  Lowering may emit string `severity`/`code`; `ElmEx.IR.Validation` uses atoms.
  `ElmEx.CoreIR.from_ir/2` normalizes to string keys for Core IR.
  """

  @type severity :: :error | :warning | String.t()

  @type code ::
          atom()
          | String.t()
          | :unsupported_op
          | :missing_declaration
          | :constructor_call_arity
          | :constructor_payload_arity
          | :preferences_schema_field_order

  alias ElmEx.CoreIR.Types

  @type t :: %{
          optional(:severity) => severity(),
          optional(:code) => code(),
          optional(:module) => String.t(),
          optional(:function) => String.t() | nil,
          optional(:message) => String.t(),
          optional(:line) => pos_integer() | nil,
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
