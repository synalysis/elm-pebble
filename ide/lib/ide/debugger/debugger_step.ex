defmodule Ide.Debugger.DebuggerStep do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.Types

  @type apply_step_fn ::
          (Types.runtime_state(), Types.surface_target(), String.t() | nil, Types.subscription_payload() | nil,
           String.t(), String.t() -> Types.runtime_state())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type host :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:normalize_target) => normalize_target_fn()
        }

  @spec apply(Types.runtime_state(), Types.step_attrs(), host()) :: Types.runtime_state()
  def apply(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      target = host.normalize_target.(Map.get(attrs, :target) || Map.get(attrs, "target"))
      message = Map.get(attrs, :message) || Map.get(attrs, "message")
      count = Attrs.parse_step_count(Map.get(attrs, :count) || Map.get(attrs, "count"))

      Enum.reduce(1..count, state, fn _, acc ->
        host.apply_step_once.(acc, target, message, nil, nil, "step")
      end)
    else
      state
    end
  end
end
