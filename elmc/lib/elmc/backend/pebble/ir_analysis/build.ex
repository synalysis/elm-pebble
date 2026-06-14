defmodule Elmc.Backend.Pebble.IRAnalysis.Build do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{AccelConfig, FeatureFlags, Types}
  alias Elmc.Backend.Pebble.IRAnalysis.{Msg, RandomGenerate}

  @spec analyze(IR.t(), Types.entry_module()) :: Types.shim_analysis()
  def analyze(%IR{} = ir, entry_module) do
    msg_constructors = Msg.constructors(ir, entry_module)

    %{
      msg_constructors: msg_constructors,
      msg_constructor_arities: Msg.constructor_arities(ir, entry_module),
      msg_constructor_payload_specs: Msg.constructor_payload_specs(ir, entry_module),
      watch_model_tags: Msg.union_constructors(ir, "Pebble.WatchInfo", "WatchModel"),
      watch_color_tags: Msg.union_constructors(ir, "Pebble.WatchInfo", "WatchColor"),
      has_view: Msg.has_view?(ir, entry_module),
      feature_flags: FeatureFlags.compute(ir, msg_constructors, entry_module),
      random_generate_tag: RandomGenerate.target_tag(ir, msg_constructors),
      accel_config: AccelConfig.from_ir(ir, entry_module)
    }
  end
end
