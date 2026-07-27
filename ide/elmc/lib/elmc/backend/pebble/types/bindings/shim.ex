defmodule Elmc.Backend.Pebble.Types.Bindings.Shim do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.{Core, FeatureFlags}

  @type shim_analysis :: %{
          required(:msg_constructors) => Core.msg_constructor_list(),
          required(:msg_constructor_arities) => Core.msg_constructor_arities(),
          required(:msg_constructor_payload_specs) => Core.msg_constructor_payload_specs(),
          required(:watch_model_tags) => Core.msg_constructor_list(),
          required(:watch_color_tags) => Core.msg_constructor_list(),
          required(:has_view) => boolean(),
          required(:feature_flags) => FeatureFlags.feature_flags(),
          required(:random_generate_tag) => Core.msg_tag(),
          required(:accel_config) => Core.accel_config()
        }
end
