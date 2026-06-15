defmodule Elmc.Backend.Pebble.FeatureFlags do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{Reachability, Types}
  alias Elmc.Backend.Pebble.FeatureFlags.{CommandFlags, DrawFlags, EventFlags, MacroTable}

  @spec compute(IR.t(), Types.msg_constructor_list(), Types.entry_module()) :: Types.feature_flags()
  def compute(%IR{} = ir, msg_constructors, entry_module) do
    ir
    |> Reachability.reachable_call_targets(entry_module)
    |> compute_from(msg_constructors)
  end

  @spec compute_from(Types.call_target_set(), Types.msg_constructor_list()) :: Types.feature_flags()
  def compute_from(targets, msg_constructors) do
    targets
    |> CommandFlags.compute()
    |> Map.merge(DrawFlags.compute(targets))
    |> Map.merge(EventFlags.compute(targets, msg_constructors))
  end

  @spec macros(Types.feature_flags()) :: Types.c_source()
  def macros(%{} = flags), do: MacroTable.render(flags)

  @spec command_flags(Types.call_target_set()) :: Types.command_feature_flags()
  defdelegate command_flags(targets), to: CommandFlags, as: :compute

  @spec draw_flags(Types.call_target_set()) :: Types.draw_feature_flags()
  defdelegate draw_flags(targets), to: DrawFlags, as: :compute
end
