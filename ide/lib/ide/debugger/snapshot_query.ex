defmodule Ide.Debugger.SnapshotQuery do
  @moduledoc false

  alias Ide.Debugger.EventLog
  alias Ide.Debugger.EventLogFilters
  alias Ide.Debugger.Types

  @type fetch_fn :: (String.t(), keyword() -> Types.runtime_state())

  @type host :: %{
          required(:fetch) => fetch_fn(),
          optional(:default_event_limit) => pos_integer()
        }

  @spec fetch(String.t(), Types.snapshot_opts(), host()) :: Types.runtime_state()
  def fetch(project_slug, opts, host)
      when is_binary(project_slug) and is_list(opts) and is_map(host) do
    limit = Keyword.get(opts, :event_limit, Map.get(host, :default_event_limit, 50))
    types = Keyword.get(opts, :types)
    since_seq = Keyword.get(opts, :since_seq)

    fetch_opts =
      [
        transform: fn prepared ->
          prepared
          |> EventLogFilters.by_types(types)
          |> EventLogFilters.since_seq(since_seq)
          |> EventLog.trim(limit)
        end
      ]
      |> maybe_put_timeout(opts)

    host.fetch.(project_slug, fetch_opts)
  end

  defp maybe_put_timeout(fetch_opts, snapshot_opts) do
    case Keyword.get(snapshot_opts, :timeout) do
      timeout when is_integer(timeout) and timeout > 0 ->
        Keyword.put(fetch_opts, :timeout, timeout)

      _ ->
        fetch_opts
    end
  end
end
