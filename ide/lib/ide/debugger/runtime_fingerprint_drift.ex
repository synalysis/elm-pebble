defmodule Ide.Debugger.RuntimeFingerprintDrift do
  @moduledoc false

  @spec backend_drift_detail(map() | nil, keyword()) :: String.t() | nil
  def backend_drift_detail(compare, opts \\ [])

  def backend_drift_detail(compare, opts) when is_map(compare) and is_list(opts) do
    max_reason_len = Keyword.get(opts, :max_reason_len, 72)
    backend_changed_key = Keyword.get(opts, :backend_changed_key, :backend_changed)
    current_backend_key = Keyword.get(opts, :current_backend_key, :current_execution_backend)

    compare_backend_keys =
      Keyword.get(opts, :compare_backend_keys, [
        :compare_execution_backend,
        :baseline_execution_backend
      ])

    current_reason_key = Keyword.get(opts, :current_reason_key, :current_external_fallback_reason)

    compare_reason_keys =
      Keyword.get(
        opts,
        :compare_reason_keys,
        [:compare_external_fallback_reason, :baseline_external_fallback_reason]
      )

    detail =
      surface_rows(compare)
      |> Enum.filter(fn {_surface, row} ->
        is_map(row) and truthy?(map_value(row, backend_changed_key))
      end)
      |> Enum.map(fn {surface, row} ->
        current_backend = row_current_value(row, current_backend_key) || "unknown"
        compare_backend = row_compare_value(row, compare_backend_keys) || "unknown"

        current_reason =
          truncate_reason(row_current_value(row, current_reason_key), max_reason_len)

        compare_reason =
          truncate_reason(row_compare_value(row, compare_reason_keys), max_reason_len)

        reason_suffix =
          cond do
            is_binary(current_reason) and is_binary(compare_reason) ->
              " [reason #{current_reason} -> #{compare_reason}]"

            is_binary(current_reason) ->
              " [reason #{current_reason}]"

            is_binary(compare_reason) ->
              " [baseline reason #{compare_reason}]"

            true ->
              ""
          end

        "#{surface}=#{current_backend}->#{compare_backend}#{reason_suffix}"
      end)
      |> Enum.join(", ")

    if detail == "", do: nil, else: detail
  end

  def backend_drift_detail(_compare, _opts), do: nil

  @spec key_target_drift_detail(map() | nil, keyword()) :: String.t() | nil
  def key_target_drift_detail(compare, opts \\ [])

  def key_target_drift_detail(compare, opts) when is_map(compare) and is_list(opts) do
    max_len = Keyword.get(opts, :max_len, 72)
    key_target_changed_key = Keyword.get(opts, :key_target_changed_key, :key_target_changed)
    current_key_key = Keyword.get(opts, :current_key_key, :current_active_target_key)
    current_source_key = Keyword.get(opts, :current_source_key, :current_active_target_key_source)

    compare_key_keys =
      Keyword.get(opts, :compare_key_keys, [
        :compare_active_target_key,
        :baseline_active_target_key
      ])

    compare_source_keys =
      Keyword.get(
        opts,
        :compare_source_keys,
        [:compare_active_target_key_source, :baseline_active_target_key_source]
      )

    detail =
      surface_rows(compare)
      |> Enum.filter(fn {_surface, row} ->
        is_map(row) and truthy?(map_value(row, key_target_changed_key))
      end)
      |> Enum.map(fn {surface, row} ->
        current_active =
          truncate_reason(row_current_value(row, current_key_key), max_len) || "nil"

        compare_active =
          truncate_reason(row_compare_value(row, compare_key_keys), max_len) || "nil"

        current_source =
          truncate_reason(row_current_value(row, current_source_key), max_len) || "nil"

        compare_source =
          truncate_reason(row_compare_value(row, compare_source_keys), max_len) || "nil"

        "#{surface}=#{current_active}(#{current_source})->#{compare_active}(#{compare_source})"
      end)
      |> Enum.join(", ")

    if detail == "", do: nil, else: detail
  end

  def key_target_drift_detail(_compare, _opts), do: nil

  @spec merge_drift_detail(String.t() | nil, String.t() | nil) :: String.t() | nil
  def merge_drift_detail(backend_detail, key_target_detail)
      when is_binary(backend_detail) and is_binary(key_target_detail) do
    "backend: #{backend_detail} | key-target: #{key_target_detail}"
  end

  def merge_drift_detail(backend_detail, _key_target_detail) when is_binary(backend_detail),
    do: "backend: #{backend_detail}"

  def merge_drift_detail(_backend_detail, key_target_detail) when is_binary(key_target_detail),
    do: "key-target: #{key_target_detail}"

  def merge_drift_detail(_backend_detail, _key_target_detail), do: nil

  @spec surface_rows(term()) :: term()
  defp surface_rows(compare) when is_map(compare) do
    case map_value(compare, :surfaces) do
      surfaces when is_map(surfaces) ->
        surfaces
        |> Enum.sort_by(fn {surface, _row} -> to_string(surface) end)

      _ ->
        []
    end
  end

  @spec row_current_value(term(), term()) :: term()
  defp row_current_value(row, key) when is_map(row) do
    case fetch_value(row, key) do
      {:ok, value} ->
        value

      :error ->
        current = map_value(row, :current)

        case fetch_value(current, strip_prefix_key(key, "current_")) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  defp row_current_value(_row, _key), do: nil

  @spec row_compare_value(term(), term()) :: term()
  defp row_compare_value(row, keys) when is_map(row) and is_list(keys) do
    compare = map_value(row, :compare)
    baseline = map_value(row, :baseline)

    Enum.reduce_while(keys, nil, fn key, _acc ->
      direct = fetch_value(row, key)
      compare_value = fetch_value(compare, strip_prefix_key(key, "compare_"))
      baseline_via_compare = fetch_value(compare, strip_prefix_key(key, "baseline_"))
      baseline_value = fetch_value(baseline, strip_prefix_key(key, "baseline_"))

      case first_fetch([direct, compare_value, baseline_via_compare, baseline_value]) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  defp row_compare_value(_row, _keys), do: nil

  @spec map_value(term(), term()) :: term()
  defp map_value(map, key) when is_map(map) do
    case fetch_value(map, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp map_value(_map, _key), do: nil

  @spec fetch_value(term(), term()) :: term()
  defp fetch_value(map, key) when is_map(map) do
    variants =
      cond do
        is_atom(key) ->
          [key, Atom.to_string(key)]

        is_binary(key) ->
          [key] ++
            case safe_existing_atom(key) do
              nil -> []
              atom_key -> [atom_key]
            end

        true ->
          [key]
      end

    Enum.reduce_while(variants, :error, fn variant, _acc ->
      if Map.has_key?(map, variant) do
        {:halt, {:ok, Map.get(map, variant)}}
      else
        {:cont, :error}
      end
    end)
  end

  defp fetch_value(_map, _key), do: :error

  @spec first_fetch(term()) :: term()
  defp first_fetch(results) when is_list(results) do
    Enum.reduce_while(results, :error, fn
      {:ok, value}, _acc -> {:halt, {:ok, value}}
      :error, _acc -> {:cont, :error}
    end)
  end

  @spec safe_existing_atom(term()) :: term()
  defp safe_existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp safe_existing_atom(_), do: nil

  @spec strip_prefix_key(term(), term()) :: term()
  defp strip_prefix_key(key, prefix) when is_atom(key) and is_binary(prefix) do
    key
    |> Atom.to_string()
    |> strip_prefix_key(prefix)
  end

  defp strip_prefix_key(key, prefix) when is_binary(key) and is_binary(prefix) do
    stripped =
      if String.starts_with?(key, prefix) do
        String.replace_prefix(key, prefix, "")
      else
        key
      end

    safe_existing_atom(stripped) || stripped
  end

  defp strip_prefix_key(key, _prefix), do: key

  @spec truthy?(term()) :: term()
  defp truthy?(value), do: value in [true, "true", 1]

  @spec truncate_reason(term(), term()) :: term()
  defp truncate_reason(reason, max_len) when is_integer(max_len) and max_len > 3 do
    text =
      cond do
        is_nil(reason) -> nil
        is_binary(reason) -> reason
        is_boolean(reason) -> to_string(reason)
        is_integer(reason) -> Integer.to_string(reason)
        is_float(reason) -> :erlang.float_to_binary(reason, [:compact])
        is_atom(reason) -> Atom.to_string(reason)
        true -> nil
      end

    cond do
      not is_binary(text) ->
        nil

      String.length(text) > max_len ->
        String.slice(text, 0, max_len - 3) <> "..."

      true ->
        text
    end
  end

  defp truncate_reason(_reason, _max_len), do: nil
end
