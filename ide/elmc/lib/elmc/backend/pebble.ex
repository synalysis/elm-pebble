defmodule Elmc.Backend.Pebble do
  @moduledoc """
  Generates a Pebble-oriented host shim around the worker adapter.
  """

  alias ElmEx.IR
  alias Elmc.Backend.Plan
  alias Elmc.Backend.CCodegen.{FunctionCallAbi, Host, IRQueries, StackEstimate, Util}
  alias Elmc.Backend.Pebble.{FeatureFlags, HeaderWriter, IRAnalysis, Kinds, SourceWriter}
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

  @spec write_pebble_shim(
          IR.t(),
          String.t(),
          PebbleTypes.entry_module(),
          Types.compile_options() | map()
        ) ::
          :ok | {:error, Types.file_error()}
  def write_pebble_shim(%IR{} = ir, out_dir, entry_module, opts \\ %{}) do
    c_dir = Path.join(out_dir, "c")
    generated_c = Map.get(opts, :generated_c, "")

    analysis = IRAnalysis.analyze(ir, entry_module, opts)

    analysis = %{
      analysis
      | feature_flags:
          FeatureFlags.augment_from_generated_c(analysis.feature_flags, generated_c, opts)
    }

    decl_map = IRQueries.function_decl_map(ir)
    direct_targets = Host.direct_command_targets(ir, opts, decl_map)

    direct_view_commands? = MapSet.member?(direct_targets, {entry_module, "view"})

    stack_safe? = direct_view_scene_stack_safe?(ir, generated_c, entry_module)

    aplite_direct_view_scene? =
      direct_view_commands? and
        (stack_safe? or prune_generic_view_for_direct_scene?(opts))

    append_fallback_enabled? =
      direct_view_commands? and
        (prune_generic_view_for_direct_scene?(opts) or aplite_direct_view_scene?)

    view_decl = Map.get(decl_map, {entry_module, "view"})

    entry_view_direct_abi? =
      entry_view_uses_direct_abi?(entry_module, c_dir, view_decl, decl_map, opts)

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
               append_fallback_enabled?: append_fallback_enabled?,
               entry_view_direct_abi?: entry_view_direct_abi?
             )
           ) do
      :ok
    end
  end

  @doc false
  @spec stream_view_fallback_needed?(
          IR.t(),
          String.t(),
          PebbleTypes.entry_module(),
          Types.compile_options() | map()
        ) ::
          boolean()
  def stream_view_fallback_needed?(ir, generated_c, entry_module, opts) do
    # Color-only and aplite pruned builds commit to streamed direct-scene commands.
    # Recompiling with stream_view_fallback pulls generic Main.view back in and overflows flash.
    if prune_generic_view_for_direct_scene?(opts) do
      false
    else
      stream_view_fallback_needed_for_dual_codegen?(ir, generated_c, entry_module, opts)
    end
  end

  @spec prune_generic_view_for_direct_scene?(keyword() | map()) :: boolean()
  defp prune_generic_view_for_direct_scene?(opts) do
    opts[:direct_render_only] == true or opts[:prune_direct_generic] == true
  end

  @spec stream_view_fallback_needed_for_dual_codegen?(
          IR.t(),
          String.t(),
          String.t(),
          keyword() | map()
        ) :: boolean()
  defp stream_view_fallback_needed_for_dual_codegen?(ir, generated_c, entry_module, opts) do
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

  # C codegen runs inside `with_emit_session`, which clears `:elmc_codegen_opts`
  # before the pebble shim is written. Read the emitted view prototype instead.
  @spec entry_view_uses_direct_abi?(
          String.t(),
          String.t(),
          map() | nil,
          map(),
          keyword() | map()
        ) :: boolean()
  defp entry_view_uses_direct_abi?(entry_module, c_dir, view_decl, decl_map, opts) do
    header_path = Path.join(c_dir, "elmc_generated.h")
    view_fn = Util.module_fn_name(entry_module, "view")

    cond do
      File.regular?(header_path) ->
        header = File.read!(header_path)

        String.contains?(header, "RC #{view_fn}(ElmcValue **out, ElmcValue *") and
          not String.contains?(header, "#{view_fn}(ElmcValue **args")

      is_map(view_decl) ->
        Plan.plan_ir_mode(opts) == :primary and
          FunctionCallAbi.primary_lowered?(view_decl, entry_module, decl_map)

      true ->
        false
    end
  end
end
