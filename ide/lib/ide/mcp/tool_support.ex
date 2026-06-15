defmodule Ide.Mcp.ToolSupport do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.Debugger.Types
  alias Ide.Mcp.WireTypes
  alias Ide.PebbleToolchain
  alias Ide.Projects
  alias Ide.Projects.Project

  @type maybe_since :: DateTime.t() | nil
  @type maybe_slug :: String.t() | nil
  @type timestamped_entry :: %{
          optional(:at) => String.t(),
          optional(atom()) => WireTypes.json_value(),
          optional(String.t()) => WireTypes.json_value()
        }

  @spec normalize_mcp_simulator_settings(Types.SimulatorSettings.wire_map()) ::
          Types.simulator_settings()
  def normalize_mcp_simulator_settings(settings) when is_map(settings) do
    Debugger.normalize_simulator_settings(settings)
  end

  def normalize_mcp_simulator_settings(_settings), do: Debugger.default_simulator_settings()

  @spec fetch_project(String.t()) :: {:ok, Project.t()} | {:error, :project_not_found}
  def fetch_project(slug) do
    case Projects.get_project_by_scope_key(slug) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  @spec project_session_key(String.t() | Project.t()) :: String.t()
  def project_session_key(%{} = project), do: Projects.scope_key(project)

  def project_session_key(slug) when is_binary(slug) do
    case Projects.get_project_by_slug(slug) do
      %{} = project -> Projects.scope_key(project)
      nil -> slug
    end
  end

  @spec map_value(Types.wire_map(), String.t()) :: WireTypes.map_value_result()
  def map_value(map, key) when is_map(map) and is_binary(key),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  def map_value(_map, _key), do: nil

  @spec map_get_any(Types.wire_map(), [atom() | String.t()], term()) :: term()
  def map_get_any(map, keys, default) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, default, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  def map_get_any(_map, _keys, default), do: default

  @spec put_opt(keyword(), atom(), WireTypes.json_value()) :: keyword()
  def put_opt(opts, _key, nil), do: opts
  def put_opt(opts, _key, ""), do: opts
  def put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @spec put_opt_map(WireTypes.json_value(), String.t(), WireTypes.json_value()) ::
          WireTypes.json_value()
  def put_opt_map(map, _key, nil), do: map
  def put_opt_map(map, _key, ""), do: map
  def put_opt_map(map, key, value), do: Map.put(map, key, value)

  @spec normalize_mcp_boolean(WireTypes.boolean_input(), boolean()) :: boolean()
  def normalize_mcp_boolean(value, default) do
    cond do
      value in [true, "true", "on", "1", 1] ->
        true

      value in [false, "false", "off", "0", 0] ->
        false

      is_list(value) ->
        case value do
          [first | _] -> normalize_mcp_boolean(first, default)
          _ -> default
        end

      true ->
        default
    end
  end

  @spec truthy?(WireTypes.json_value()) :: boolean()
  def truthy?(value) do
    value in [true, 1, "1", "true", "TRUE", "True"]
  end

  @spec parse_limit(WireTypes.limit_input()) :: pos_integer()
  def parse_limit(value) when is_integer(value), do: clamp_limit(value)

  def parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> clamp_limit(parsed)
      _ -> 20
    end
  end

  def parse_limit(_), do: 20

  @spec clamp_limit(integer()) :: pos_integer()
  def clamp_limit(limit) when limit < 1, do: 1
  def clamp_limit(limit) when limit > 200, do: 200
  def clamp_limit(limit), do: limit

  @spec parse_since(WireTypes.since_input()) :: {:ok, maybe_since()} | {:error, String.t()}
  def parse_since(nil), do: {:ok, nil}
  def parse_since(""), do: {:ok, nil}

  def parse_since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, "invalid since timestamp (expected ISO8601)"}
    end
  end

  def parse_since(_), do: {:error, "invalid since timestamp (expected ISO8601)"}

  @spec parse_trace_id(WireTypes.trace_id_input()) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  def parse_trace_id(nil), do: {:ok, nil}
  def parse_trace_id(""), do: {:ok, nil}
  def parse_trace_id(value) when is_binary(value), do: {:ok, value}
  def parse_trace_id(_), do: {:error, "invalid trace_id (expected string)"}

  @spec parse_optional_slug(WireTypes.slug_input()) :: {:ok, maybe_slug()} | {:error, String.t()}
  def parse_optional_slug(nil), do: {:ok, nil}
  def parse_optional_slug(""), do: {:ok, nil}
  def parse_optional_slug(value) when is_binary(value), do: {:ok, value}
  def parse_optional_slug(_), do: {:error, "invalid slug (expected string)"}

  @spec parse_positive_integer(WireTypes.limit_input(), pos_integer()) :: pos_integer()
  def parse_positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value

  def parse_positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  def parse_positive_integer(_value, fallback), do: fallback

  @spec format_since(maybe_since()) :: String.t() | nil
  def format_since(nil), do: nil
  def format_since(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @spec filter_since([timestamped_entry()], maybe_since()) :: [timestamped_entry()]
  def filter_since(entries, nil), do: entries

  def filter_since(entries, %DateTime{} = since),
    do: Enum.filter(entries, &keep_since?(&1, since))

  @spec keep_since?(timestamped_entry(), maybe_since()) :: boolean()
  def keep_since?(_entry, nil), do: true

  def keep_since?(entry, %DateTime{} = since) do
    case entry_datetime(entry) do
      {:ok, dt} -> DateTime.compare(dt, since) in [:eq, :gt]
      :error -> false
    end
  end

  @spec entry_datetime(timestamped_entry()) :: {:ok, DateTime.t()} | :error
  def entry_datetime(entry) when is_map(entry) do
    at = Map.get(entry, :at) || Map.get(entry, "at")

    if is_binary(at) do
      case DateTime.from_iso8601(at) do
        {:ok, dt, _offset} -> {:ok, dt}
        _ -> :error
      end
    else
      :error
    end
  end

  @spec cache_latest_result_field(module(), String.t(), maybe_since(), atom()) ::
          WireTypes.json_value() | nil
  def cache_latest_result_field(cache, slug, since, field)
      when is_binary(slug) and is_atom(field) do
    case cache.latest(slug) do
      {:ok, entry} ->
        if keep_since?(entry, since) do
          entry
          |> Map.get(:result, %{})
          |> Map.get(field)
        end

      _ ->
        nil
    end
  end

  @spec publish_target_platforms(Project.t()) :: [String.t()]
  def publish_target_platforms(project) do
    defaults = Map.get(project, :release_defaults) || %{}
    allowed = PebbleToolchain.supported_emulator_targets()
    allowed_set = MapSet.new(allowed)

    defaults
    |> Map.get("target_platforms", allowed)
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&MapSet.member?(allowed_set, &1))
    |> Enum.uniq()
    |> case do
      [] -> allowed
      targets -> targets
    end
  end
end
