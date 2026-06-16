defmodule Ide.Debugger.CompanionBootstrapLock do
  @moduledoc false

  @table :debugger_companion_bootstrap_inflight

  @spec try_acquire(String.t()) :: boolean()
  def try_acquire(scope_key) when is_binary(scope_key) do
    ensure_table()
    :ets.insert_new(@table, {scope_key, true})
  end

  @spec release(String.t()) :: :ok
  def release(scope_key) when is_binary(scope_key) do
    ensure_table()
    :ets.delete(@table, scope_key)
    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end
end
