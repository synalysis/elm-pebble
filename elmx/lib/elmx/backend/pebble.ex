defmodule Elmx.Backend.Pebble do
  @moduledoc """
  Pebble UI/cmd/view codegen (Phase 3 expansion).

  v0: platform calls delegate to `Elmx.Runtime.Pebble` stubs at runtime.
  """

  @spec write_pebble_shim(ElmEx.IR.t(), String.t(), String.t()) :: :ok
  def write_pebble_shim(_ir, _out_dir, _entry_module), do: :ok
end
