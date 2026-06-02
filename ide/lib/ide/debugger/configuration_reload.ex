defmodule Ide.Debugger.ConfigurationReload do
  @moduledoc false

  alias Ide.Debugger.CompanionConfiguration
  alias Ide.Debugger.Types

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type host :: %{required(:ensure_phone_state) => ensure_phone_fn()}

  @spec apply(Types.runtime_state(), String.t(), host()) :: Types.runtime_state()
  def apply(state, project_slug, host)
      when is_map(state) and is_binary(project_slug) and is_map(host) do
    state
    |> host.ensure_phone_state.()
    |> update_in([:companion, :model], &CompanionConfiguration.drop_from_model/1)
    |> CompanionConfiguration.attach_to_state(project_slug)
  end
end
