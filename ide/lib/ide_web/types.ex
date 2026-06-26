defmodule IdeWeb.Types do
  @moduledoc false

  @type quoted :: Macro.t()

  @type static_path_list :: [String.t()]

  @type periodic_measurement :: {module(), atom(), [atom() | String.t() | integer()]}

  @type periodic_measurements :: [periodic_measurement()]

  @type json_scalar :: String.t() | integer() | float() | boolean() | nil

  @type json_value ::
          json_scalar() | [json_value()] | %{optional(String.t()) => json_value()}

  @typedoc "Phoenix wire params with string keys (routes, controllers, LiveView)."
  @type wire_params :: %{optional(String.t()) => json_value()}

  @typedoc "Phoenix error view render assigns (unused by default implementations)."
  @type error_render_assigns :: %{optional(String.t()) => json_value()}
end
