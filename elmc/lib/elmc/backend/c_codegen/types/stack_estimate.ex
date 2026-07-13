defmodule Elmc.Backend.CCodegen.Types.StackEstimate do
  @moduledoc """
  Stack-risk report maps from `Elmc.Backend.CCodegen.StackEstimate`.
  """

  @type risk_level :: :ok | :warn | :risk

  @type risk_reason ::
          :list_hof
          | :lambda
          | :self_recursion
          | :many_temporaries
          | :many_boxed_locals
          | :list_hof_runtime
          | :list_drop

  @type summary :: %{
          required(:ok) => non_neg_integer(),
          required(:warn) => non_neg_integer(),
          required(:risk) => non_neg_integer()
        }

  @type runtime_call_counts :: %{String.t() => non_neg_integer()}

  @type linked_binary_slot :: Elmc.Backend.CCodegen.Types.LinkedBinary.wire_map()

  @type code_size_indicators :: %{
          required(:generated_c_bytes) => non_neg_integer(),
          required(:generated_c_lines) => pos_integer(),
          required(:generic_function_defs) => non_neg_integer(),
          required(:direct_command_defs) => non_neg_integer(),
          required(:boxed_tmp_declarations) => non_neg_integer(),
          required(:closure_allocations) => non_neg_integer(),
          required(:runtime_calls) => runtime_call_counts(),
          required(:linked_binary) => linked_binary_slot()
        }

  @type report_scalar :: integer() | boolean() | String.t() | nil

  @type report_value ::
          report_scalar()
          | [report_value()]
          | %{optional(String.t()) => report_value(), optional(atom()) => report_value()}

  @type function_entry :: %{
          required(:function) => String.t(),
          required(:score) => non_neg_integer(),
          required(:reasons) => [risk_reason()],
          required(:level) => risk_level(),
          optional(:c_tmp_max) => non_neg_integer(),
          optional(:c_boxed_locals) => non_neg_integer(),
          optional(atom()) => report_scalar(),
          optional(String.t()) => report_scalar()
        }

  @type t :: %{
          required(:summary) => summary(),
          required(:code_size_indicators) => code_size_indicators(),
          required(:functions) => [function_entry()]
        }

  @type wire_map :: t() | %{optional(String.t()) => report_value(), optional(atom()) => report_value()}
end
