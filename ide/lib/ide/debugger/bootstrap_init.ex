defmodule Ide.Debugger.BootstrapInit do
  @moduledoc false

  alias Ide.Debugger.Types

  @parser_only_key :debugger_parser_only_init
  @defer_surface_effects_key :debugger_defer_init_surface_effects

  @spec with_companion_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def with_companion_bootstrap_flags(state) when is_map(state) do
    state
    |> Map.put(:debugger_skip_blocking_compile, true)
    |> Map.put(@parser_only_key, true)
    |> Map.put(@defer_surface_effects_key, true)
  end

  @spec clear_companion_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def clear_companion_bootstrap_flags(state) when is_map(state) do
    state
    |> Map.delete(:debugger_skip_blocking_compile)
    |> Map.delete(@parser_only_key)
    |> Map.delete(@defer_surface_effects_key)
  end

  @spec clear_session_bootstrap_flags(Types.runtime_state()) :: Types.runtime_state()
  def clear_session_bootstrap_flags(state) when is_map(state), do: clear_companion_bootstrap_flags(state)

  @spec parser_only?(Types.runtime_state()) :: boolean()
  def parser_only?(state) when is_map(state), do: Map.get(state, @parser_only_key) == true
  def parser_only?(_), do: false

  @spec defer_surface_effects?(Types.runtime_state()) :: boolean()
  def defer_surface_effects?(state) when is_map(state), do: Map.get(state, @defer_surface_effects_key) == true
  def defer_surface_effects?(_), do: false

  @spec take_defer_surface_effects(Types.runtime_state()) :: {boolean(), Types.runtime_state()}
  def take_defer_surface_effects(state) when is_map(state) do
    {defer_surface_effects?(state), Map.delete(state, @defer_surface_effects_key)}
  end
end
