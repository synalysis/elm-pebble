defmodule Elmc.Backend.CCodegen.Types.Hoist do
  @moduledoc """
  Cache keys for `Elmc.Backend.CCodegen.Hoist` native bool/int hoisting.
  """

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes

  @type binding_key :: String.t() | CCodegenTypes.ir_expr()
  @type case_tag :: atom() | String.t() | nil
  @type other_op :: atom() | nil

  @type key ::
          {:case, case_tag(), key()}
          | {:qualified, String.t(), [key()]}
          | {:call, String.t(), [key()]}
          | {:field, key(), String.t()}
          | {:compare, atom() | String.t(), key(), key()}
          | {:var, binding_key()}
          | {:int, integer()}
          | {:char, String.t() | integer()}
          | {:c_int, String.t()}
          | {:minmax, String.t(), [key()]}
          | {:other, other_op()}
          | CCodegenTypes.ir_expr()

  @type native_int_map :: %{key() => String.t()}
end
