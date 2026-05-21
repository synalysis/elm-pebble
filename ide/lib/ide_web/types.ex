defmodule IdeWeb.Types do
  @moduledoc false

  @type quoted :: Macro.t()

  @type static_path_list :: [String.t()]

  @type periodic_measurement :: {module(), atom(), list()}

  @type periodic_measurements :: [periodic_measurement()]
end
