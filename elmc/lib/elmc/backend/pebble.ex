defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{HeaderWriter, IRAnalysis, Kinds, SourceWriter}
  alias Elmc.Backend.Pebble.Types, as: PebbleTypes
  alias Elmc.Types

  @spec draw_kind_id!(Kinds.draw_kind()) :: non_neg_integer()
  defdelegate draw_kind_id!(kind), to: Kinds

  @spec draw_kind_c_name!(Kinds.draw_kind() | non_neg_integer()) :: PebbleTypes.c_macro_name()
  defdelegate draw_kind_c_name!(kind), to: Kinds

  @spec command_kind_id!(Kinds.command_kind()) :: non_neg_integer()
  defdelegate command_kind_id!(kind), to: Kinds

  @spec command_kind_c_name!(Kinds.command_kind() | non_neg_integer()) :: PebbleTypes.c_macro_name()
  defdelegate command_kind_c_name!(kind), to: Kinds

  @spec run_mode_id!(Kinds.run_mode()) :: non_neg_integer()
  defdelegate run_mode_id!(mode), to: Kinds

  @spec button_id!(Kinds.button_id()) :: non_neg_integer()
  defdelegate button_id!(button), to: Kinds

  @spec accel_axis_id!(Kinds.accel_axis()) :: non_neg_integer()
  defdelegate accel_axis_id!(axis), to: Kinds

  @spec ui_node_kind_id!(Kinds.ui_node_kind()) :: non_neg_integer()
  defdelegate ui_node_kind_id!(kind), to: Kinds

  @spec write_pebble_shim(IR.t(), String.t(), PebbleTypes.entry_module()) ::
          :ok | {:error, Types.file_error()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module) do
    c_dir = Path.join(out_dir, "c")
    analysis = IRAnalysis.analyze(ir, entry_module)

    with :ok <- File.mkdir_p(c_dir),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.h"),
             HeaderWriter.generate(analysis, entry_module)
           ),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.c"),
             SourceWriter.generate(analysis, entry_module)
           ) do
      :ok
    end
  end
end
