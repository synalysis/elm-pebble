defmodule Ide.Debugger.StepResult do
  @moduledoc """
  Result of a single debugger runtime step: updated session state and surface.
  """

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.RuntimeState

  @enforce_keys [:state, :surface]
  defstruct [:state, :surface]

  @type t :: %__MODULE__{
          state: RuntimeState.t() | RuntimeState.wire_map(),
          surface: Surface.t()
        }

  @spec new(Types.runtime_state(), %Surface{}) :: t()
  def new(state, %Surface{} = surface) when is_map(state) do
    %__MODULE__{state: state, surface: surface}
  end

  @spec state(t()) :: RuntimeState.t() | RuntimeState.wire_map()
  def state(%__MODULE__{state: state}), do: state
end
