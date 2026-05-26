defmodule Ide.Debugger.TraceExchange.Import do
  @moduledoc false

  alias Ide.Debugger.SimulatorSettings
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TraceExchange.Wire
  alias Ide.Debugger.Types

  @type runtime_event :: Types.runtime_event()
  @type debugger_event :: Types.debugger_event()

  @type parse_opts :: [
          parse_watch_profile_id: (Types.wire_input() -> Types.watch_profile() | nil),
          parse_cursor_seq: (Types.wire_input() -> non_neg_integer() | nil)
        ]

  @spec decode_body(String.t() | map()) :: {:ok, map()} | {:error, Types.protocol_error()}
  def decode_body(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, body} when is_map(body) -> {:ok, body}
      {:ok, _} -> {:error, :invalid_trace}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def decode_body(body) when is_map(body), do: {:ok, body}

  @spec validate_body(Types.import_trace_body()) :: :ok | {:error, Types.protocol_error()}
  def validate_body(body) do
    version = Map.get(body, "export_version")

    if version == 1 and is_list(Map.get(body, "events")) and is_map(Map.get(body, "watch")) and
         is_map(Map.get(body, "companion")) and is_integer(Map.get(body, "seq")) do
      :ok
    else
      {:error, :invalid_trace}
    end
  end

  @spec maybe_match_slug(Types.import_trace_body(), String.t(), keyword()) :: :ok | {:error, Types.protocol_error()}
  def maybe_match_slug(body, project_slug, opts) do
    if Keyword.get(opts, :strict_slug, true) do
      if Map.get(body, "project_slug") == project_slug do
        :ok
      else
        {:error, :slug_mismatch}
      end
    else
      :ok
    end
  end

  @spec parse_state(Types.import_trace_body(), parse_opts()) :: map()
  def parse_state(body, opts) when is_map(body) and is_list(opts) do
    parse_watch_profile_id = Keyword.fetch!(opts, :parse_watch_profile_id)
    parse_cursor_seq = Keyword.fetch!(opts, :parse_cursor_seq)

    events =
      body
      |> Map.get("events", [])
      |> Enum.sort_by(&Map.get(&1, "seq"))
      |> Enum.map(&import_event/1)
      |> Enum.reverse()

    %{
      running: Map.get(body, "running", false) == true,
      revision: Map.get(body, "revision"),
      watch_profile_id: parse_watch_profile_id.(Map.get(body, "watch_profile_id")),
      launch_context: Wire.normalize_term(Map.get(body, "launch_context") || %{}),
      simulator_settings: SimulatorSettings.normalize(Map.get(body, "simulator_settings") || %{}),
      watch: import_watch(Map.get(body, "watch", %{})),
      companion: import_companion(Map.get(body, "companion", %{})),
      phone: import_phone(Map.get(body, "phone", %{})),
      disabled_subscriptions:
        Map.get(body, "disabled_subscriptions", []) |> List.wrap() |> Enum.filter(&is_map/1),
      events: events,
      debugger_timeline: import_debugger_timeline(Map.get(body, "debugger_timeline", [])),
      debugger_seq:
        parse_cursor_seq.(Map.get(body, "debugger_seq")) ||
          infer_debugger_seq(Map.get(body, "debugger_timeline", [])),
      seq: parse_cursor_seq.(Map.get(body, "seq")) || 0
    }
  end

  defp import_event(map) when is_map(map) do
    %{
      seq: Map.get(map, "seq"),
      type: Map.get(map, "type"),
      payload: Map.get(map, "payload") || %{},
      watch: import_watch(Map.get(map, "watch") || %{}),
      companion: import_companion(Map.get(map, "companion") || %{}),
      phone: import_phone(Map.get(map, "phone") || %{})
    }
  end

  defp import_debugger_timeline(rows) when is_list(rows) do
    rows
    |> Enum.filter(&is_map/1)
    |> Enum.map(&import_debugger_row/1)
    |> Enum.filter(fn row -> is_integer(row.seq) and row.seq >= 0 end)
    |> Enum.sort_by(& &1.seq, :desc)
  end

  defp import_debugger_timeline(_rows), do: []

  defp import_debugger_row(map) when is_map(map) do
    %{
      seq: Map.get(map, "seq") || Map.get(map, :seq),
      raw_seq: Map.get(map, "raw_seq") || Map.get(map, :raw_seq) || 0,
      type: Map.get(map, "type") || Map.get(map, :type) || "update",
      target: Map.get(map, "target") || Map.get(map, :target) || "watch",
      message: Map.get(map, "message") || Map.get(map, :message) || "",
      message_source: Map.get(map, "message_source") || Map.get(map, :message_source),
      watch: import_watch(Map.get(map, "watch") || Map.get(map, :watch) || %{}),
      companion: import_companion(Map.get(map, "companion") || Map.get(map, :companion) || %{}),
      phone: import_phone(Map.get(map, "phone") || Map.get(map, :phone) || %{})
    }
  end

  defp infer_debugger_seq(rows) when is_list(rows) do
    rows
    |> Enum.map(fn
      %{"seq" => seq} -> seq
      %{seq: seq} -> seq
      _ -> 0
    end)
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> 0 end)
  end

  defp infer_debugger_seq(_rows), do: 0

  defp import_watch(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "root",
              "children" => []
            }
      })
    )
  end

  defp import_companion(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "CompanionRoot",
              "label" => "idle",
              "children" => []
            }
      })
    )
  end

  defp import_phone(map) when is_map(map) do
    Surface.to_map(
      Surface.from_map(%{
        model: Map.get(map, "model") || %{},
        shell: Map.get(map, "shell") || %{},
        last_message: Map.get(map, "last_message"),
        protocol_messages: Map.get(map, "protocol_messages") || [],
        view_tree:
          Map.get(map, "view_tree") ||
            %{
              "type" => "PhoneRoot",
              "label" => "idle",
              "children" => []
            }
      })
    )
  end
end
