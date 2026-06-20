defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.{Host, IRQueries}
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

  @spec write_pebble_shim(IR.t(), String.t(), PebbleTypes.entry_module(), map()) ::
          :ok | {:error, Types.file_error()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")
    analysis = IRAnalysis.analyze(ir, entry_module)
    decl_map = IRQueries.function_decl_map(ir)
    direct_targets = Host.direct_command_targets(ir, opts, decl_map)

    aplite_direct_view_scene? =
      MapSet.member?(direct_targets, {entry_module, "view"})

    with :ok <- File.mkdir_p(c_dir),
         :ok <-
           File.write(
             Path.join(c_dir, "elmc_pebble.h"),
             HeaderWriter.generate(analysis, entry_module,
               aplite_direct_view_scene: aplite_direct_view_scene?
             )
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
