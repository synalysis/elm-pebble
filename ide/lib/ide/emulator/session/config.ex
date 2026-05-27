defmodule Ide.Emulator.Session.Config do
  @moduledoc false

  @spec config(atom(), term()) :: term()
  def config(key, default),
    do: Application.get_env(:ide, Ide.Emulator.Session, []) |> Keyword.get(key, default)

  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled, true) == true

  @spec start_processes?() :: boolean()
  def start_processes?, do: config(:start_processes, true) == true
end
