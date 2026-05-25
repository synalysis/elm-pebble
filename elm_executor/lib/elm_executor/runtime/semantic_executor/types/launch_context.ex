defmodule ElmExecutor.Runtime.SemanticExecutor.Types.LaunchContext do
  @moduledoc """
  Launch context passed to `Main.init` during debugger init evaluation (runtime map).
  """

  @type screen_shape :: %{
          optional(:is_round) => boolean(),
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer(),
          optional(atom()) => term()
        }

  @type t :: %{
          optional(:shape) => screen_shape() | map(),
          optional(:supports_health) => boolean(),
          optional(:watch_model) => String.t(),
          optional(:launch_reason) => String.t(),
          optional(:screen) => map(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
