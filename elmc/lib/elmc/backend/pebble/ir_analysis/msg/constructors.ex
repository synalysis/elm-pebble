defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.Constructors do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.IRAnalysis.Msg.Constructors.{Arities, PayloadSpecs, Tags}
  alias Elmc.Backend.Pebble.Types

  @spec constructors(IR.t(), Types.entry_module()) :: Types.msg_constructor_list()
  def constructors(%IR{} = ir, entry_module), do: Tags.from_ir(ir, entry_module)

  @spec constructor_arities(IR.t(), Types.entry_module()) :: Types.msg_constructor_arities()
  def constructor_arities(%IR{} = ir, entry_module), do: Arities.from_ir(ir, entry_module)

  @spec constructor_payload_specs(IR.t(), Types.entry_module()) ::
          Types.msg_constructor_payload_specs()
  def constructor_payload_specs(%IR{} = ir, entry_module),
    do: PayloadSpecs.from_ir(ir, entry_module)
end
