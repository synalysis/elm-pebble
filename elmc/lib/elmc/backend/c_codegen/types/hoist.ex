defmodule Elmc.Backend.CCodegen.Types.Hoist do
  @moduledoc """
  Cache keys for `Elmc.Backend.CCodegen.Hoist` native bool/int hoisting.
  """

  @type key ::
          {:case, term(), key()}
          | {:qualified, String.t(), [key()]}
          | {:call, String.t(), [key()]}
          | {:field, key(), String.t()}
          | {:compare, atom() | String.t(), key(), key()}
          | {:var, term()}
          | {:int, integer()}
          | {:char, String.t() | integer()}
          | {:c_int, term()}
          | {:minmax, String.t(), [key()]}
          | {:other, term()}
          | term()

  @type native_int_map :: %{key() => String.t()}
end
