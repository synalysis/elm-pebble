defmodule Elmc.Backend.Pebble.IRAnalysis.Build do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{AccelConfig, FeatureFlags, Types}
  alias Elmc.Backend.Pebble.IRAnalysis.Msg
  alias Elmc.Types, as: ElmcTypes

  @spec analyze(IR.t(), Types.entry_module()) :: Types.shim_analysis()
  def analyze(%IR{} = ir, entry_module), do: analyze(ir, entry_module, %{})

  @spec analyze(IR.t(), Types.entry_module(), ElmcTypes.compile_options() | map()) ::
          Types.shim_analysis()
  def analyze(%IR{} = ir, entry_module, opts) when is_map(opts) do
    msg_constructors = Msg.constructors(ir, entry_module)

    %{
      msg_constructors: msg_constructors,
      msg_constructor_arities: Msg.constructor_arities(ir, entry_module),
      msg_constructor_payload_specs: Msg.constructor_payload_specs(ir, entry_module),
      watch_model_tags: Msg.union_constructors(ir, "Pebble.WatchInfo", "WatchModel"),
      watch_color_tags: Msg.union_constructors(ir, "Pebble.WatchInfo", "WatchColor"),
      has_view: Msg.has_view?(ir, entry_module),
      feature_flags: FeatureFlags.compute(ir, msg_constructors, entry_module, opts),
      random_generate_tag: 0,
      accel_config: AccelConfig.from_ir(ir, entry_module)
    }
  end
end
