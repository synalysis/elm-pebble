defmodule Ide.Debugger.BootstrapInit do
  @moduledoc false

  alias Ide.Debugger.Types

  @defer_surface_effects_key :debugger_defer_init_surface_effects

  @spec with_companion_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def with_companion_bootstrap_flags(state) when is_map(state) do
    state
    |> Map.put(:debugger_skip_blocking_compile, true)
    |> Map.put(@defer_surface_effects_key, true)
  end

  @spec clear_companion_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def clear_companion_bootstrap_flags(state) when is_map(state) do
    Map.delete(state, :debugger_skip_blocking_compile)
  end

  @spec with_skip_blocking_compile_flags(Types.runtime_state()) :: Types.runtime_state()
  def with_skip_blocking_compile_flags(state) when is_map(state) do
    Map.put(state, :debugger_skip_blocking_compile, true)
  end

  @spec clear_skip_blocking_compile_flags(Types.runtime_state()) :: Types.runtime_state()
  def clear_skip_blocking_compile_flags(state) when is_map(state) do
    Map.delete(state, :debugger_skip_blocking_compile)
  end

  @spec discard_defer_surface_effects(Types.runtime_state()) :: Types.runtime_state()
  def discard_defer_surface_effects(state) when is_map(state) do
    Map.delete(state, @defer_surface_effects_key)
  end

  @spec clear_session_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def clear_session_bootstrap_flags(state) when is_map(state),
    do: clear_companion_bootstrap_flags(state)

  @spec parser_only?(Types.runtime_state()) :: false
  def parser_only?(_state), do: false

  @spec defer_surface_effects?(Types.runtime_state()) :: boolean()
  def defer_surface_effects?(state) when is_map(state),
    do: Map.get(state, @defer_surface_effects_key) == true

  def defer_surface_effects?(_), do: false

  @spec take_defer_surface_effects(Types.runtime_state()) :: {boolean(), Types.runtime_state()}
  def take_defer_surface_effects(state) when is_map(state) do
    {defer_surface_effects?(state), Map.delete(state, @defer_surface_effects_key)}
  end
end
