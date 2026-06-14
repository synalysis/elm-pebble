defmodule Elmc.Backend.Pebble.AccelConfig do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.AccelConfig.{Resolve, Walker}
  alias Elmc.Backend.Pebble.Types

  @spec from_ir(IR.t(), Types.entry_module()) :: Types.accel_config()
  defdelegate from_ir(ir, entry_module), to: Walker

  @spec default_accel_config() :: Types.accel_config()
  defdelegate default_accel_config(), to: Walker

  @spec bindings_from_ir(IR.t()) :: Types.record_literal_bindings()
  defdelegate bindings_from_ir(ir), to: Resolve
end
