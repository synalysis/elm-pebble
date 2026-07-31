defmodule Elmc.Backend.Pebble.FeatureFlags do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{Reachability, Types}
  alias Elmc.Backend.Pebble.FeatureFlags.{CommandFlags, DrawFlags, EventFlags, MacroTable}
  alias Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Compact
  alias Elmc.Backend.Pebble.Kinds.{CNames, Tables}
  alias Elmc.Types, as: ElmcTypes

  @spec compute(IR.t(), Types.msg_constructor_list(), Types.entry_module()) ::
          Types.feature_flags()
  def compute(%IR{} = ir, msg_constructors, entry_module) do
    compute(ir, msg_constructors, entry_module, %{})
  end

  @spec compute(
          IR.t(),
          Types.msg_constructor_list(),
          Types.entry_module(),
          ElmcTypes.compile_options() | map()
        ) :: Types.feature_flags()
  def compute(%IR{} = ir, msg_constructors, entry_module, opts) when is_map(opts) do
    ir
    |> Reachability.reachable_call_targets(entry_module)
    |> compute_from(msg_constructors, opts)
  end

  @spec compute_from(Types.call_target_set(), Types.msg_constructor_list()) ::
          Types.feature_flags()
  def compute_from(targets, msg_constructors), do: compute_from(targets, msg_constructors, %{})

  @spec compute_from(
          Types.call_target_set(),
          Types.msg_constructor_list(),
          ElmcTypes.compile_options() | map()
        ) :: Types.feature_flags()
  def compute_from(targets, msg_constructors, opts) when is_map(opts) do
    targets
    |> CommandFlags.compute()
    |> Map.merge(DrawFlags.compute(targets, opts))
    |> Map.merge(EventFlags.compute(targets, msg_constructors))
  end

  @spec augment_from_generated_c(Types.feature_flags(), String.t()) :: Types.feature_flags()
  def augment_from_generated_c(flags, generated_c),
    do: augment_from_generated_c(flags, generated_c, %{})

  @spec augment_from_generated_c(
          Types.feature_flags(),
          String.t(),
          ElmcTypes.compile_options() | map()
        ) :: Types.feature_flags()
  def augment_from_generated_c(flags, generated_c, opts)
      when is_binary(generated_c) and is_map(opts) do
    updated =
      flags
      |> augment_draw_from_generated_c(generated_c)
      |> augment_command_flags_from_generated_c(generated_c)

    Map.merge(updated, Compact.compute(updated, opts))
  end

  def augment_from_generated_c(flags, _, _), do: flags

  @spec augment_draw_from_generated_c(Types.feature_flags(), String.t()) :: Types.feature_flags()
  defp augment_draw_from_generated_c(flags, generated_c) do
    if String.contains?(generated_c, "ELMC_RENDER_OP_TEXT_INT_WITH_FONT") do
      flags
      |> Map.put(:draw_text_int, true)
      |> Map.put(:draw_text_any, true)
    else
      flags
    end
  end

  @spec augment_command_flags_from_generated_c(Types.feature_flags(), String.t()) ::
          Types.feature_flags()
  defp augment_command_flags_from_generated_c(flags, generated_c) do
    Tables.command_kinds()
    |> Enum.reduce(flags, fn {kind, _id}, acc ->
      flag_key = :"cmd_#{kind}"

      if Map.has_key?(acc, flag_key) and
           String.contains?(generated_c, CNames.command_kind_c_name!(kind)) do
        Map.put(acc, flag_key, true)
      else
        acc
      end
    end)
  end

  @spec macros(Types.feature_flags()) :: Types.c_source()
  def macros(%{} = flags), do: MacroTable.render(flags)

  @spec command_flags(Types.call_target_set()) :: Types.command_feature_flags()
  defdelegate command_flags(targets), to: CommandFlags, as: :compute

  @spec draw_flags(Types.call_target_set()) :: Types.draw_feature_flags()
  defdelegate draw_flags(targets), to: DrawFlags, as: :compute
end
