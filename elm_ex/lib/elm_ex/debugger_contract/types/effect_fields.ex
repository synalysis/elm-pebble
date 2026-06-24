defmodule ElmEx.DebuggerContract.Types.EffectFields do
  @moduledoc """
  Effect metadata extracted from Core IR by `EffectsFromCoreIR.effect_fields/2`.

  Only non-empty fields are present. Runtime maps use string keys.
  """

  alias ElmEx.DebuggerContract.CmdCall

  @type cmd_call_rows :: [CmdCall.wire_map()]
  @type outline_rows :: [String.t()]

  @typedoc """
  Known keys: `"subscription_calls"`, `"subscription_ops"`, `"init_cmd_ops"`,
  `"init_cmd_calls"`, `"update_cmd_ops"`, `"update_cmd_calls"`.
  """
  @type t :: %{
          optional(atom()) => cmd_call_rows() | outline_rows(),
          optional(String.t()) => cmd_call_rows() | outline_rows()
        }

  @type wire_map :: t()
end
