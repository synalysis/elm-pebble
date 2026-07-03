defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR
  alias Elmc.Backend.CCodegen.{Host, IRQueries, StackEstimate}
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

    generated_c = Map.get(opts, :generated_c, "")

    aplite_direct_view_scene? =
      MapSet.member?(direct_targets, {entry_module, "view"}) and
        direct_view_scene_stack_safe?(ir, generated_c, entry_module)

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
             SourceWriter.generate(analysis, entry_module,
               append_fallback_enabled?: aplite_direct_view_scene?
             )
           ) do
      :ok
    end
  end

  @doc false
  @spec stream_view_fallback_needed?(IR.t(), String.t(), PebbleTypes.entry_module(), map()) ::
          boolean()
  def stream_view_fallback_needed?(ir, generated_c, entry_module, opts) do
    decl_map = IRQueries.function_decl_map(ir)
    direct_targets = Host.direct_command_targets(ir, opts, decl_map)
    view_target = {entry_module, "view"}

    MapSet.member?(direct_targets, view_target) and
      not direct_view_scene_stack_safe?(ir, generated_c, entry_module)
  end

  # Stack-heavy direct scene encoding nests large owned-slot frames (for example
  # drawDial) on the timer stack and can fault on watch hardware before the first
  # frame. Fall back to the streamed virtual-ui scene path when analysis marks any
  # entry-module render helper as :risk.
  @spec direct_view_scene_stack_safe?(IR.t(), String.t(), PebbleTypes.entry_module()) ::
          boolean()
  defp direct_view_scene_stack_safe?(_ir, generated_c, _entry_module)
       when not is_binary(generated_c) or generated_c == "" do
    true
  end

  defp direct_view_scene_stack_safe?(ir, generated_c, entry_module) do
    prefix = entry_module <> "."

    ir
    |> StackEstimate.report(generated_c)
    |> Map.fetch!(:functions)
    |> Enum.all?(fn entry ->
      entry.level != :risk or not String.starts_with?(entry.function, prefix)
    end)
  end
end
