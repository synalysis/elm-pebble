defmodule Ide.Debugger.ProtocolResolutionCtx do
  @moduledoc """
  Typed context for resolving companion protocol constructor arguments.
  """

  alias Ide.Debugger.Types

  @enforce_keys [:direction, :runtime_model, :simulator_settings]
  defstruct [
    :direction,
    :protocol_ctor,
    :arg_index,
    :runtime_model,
    :simulator_settings,
    :message_value
  ]

  @type direction :: :watch_to_phone | :phone_to_watch

  @type t :: %__MODULE__{
          direction: direction(),
          protocol_ctor: String.t() | nil,
          arg_index: non_neg_integer() | nil,
          runtime_model: Types.inner_runtime_model(),
          simulator_settings: Types.simulator_settings(),
          message_value: Types.protocol_message() | map() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    struct!(__MODULE__, opts)
  end

  @spec with_arg_index(t(), non_neg_integer()) :: t()
  def with_arg_index(%__MODULE__{} = ctx, index) when is_integer(index) and index >= 0 do
    %{ctx | arg_index: index}
  end

  @spec to_legacy_map(t()) :: map()
  def to_legacy_map(%__MODULE__{} = ctx) do
    %{
      message_value: ctx.message_value,
      runtime_model: ctx.runtime_model,
      simulator_settings: ctx.simulator_settings,
      protocol_ctor: ctx.protocol_ctor,
      arg_index: ctx.arg_index,
      direction: ctx.direction
    }
  end
end
