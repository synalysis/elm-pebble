defmodule Ide.Emulator.RuntimeStats do
  @moduledoc false

  @type t :: %{
          scene_bytes: non_neg_integer(),
          scene_cmds: non_neg_integer(),
          scene_cap: non_neg_integer(),
          heap_free: non_neg_integer(),
          heap_free_min: non_neg_integer()
        }

  @prefix "elmc-stats"
  @required_keys [:scene_bytes, :scene_cmds, :scene_cap, :heap_free, :heap_free_min]
  @key_atoms %{
    "scene_bytes" => :scene_bytes,
    "scene_cmds" => :scene_cmds,
    "scene_cap" => :scene_cap,
    "heap_free" => :heap_free,
    "heap_free_min" => :heap_free_min
  }

  @spec parse(String.t()) :: t() | nil
  def parse(line) when is_binary(line) do
    body = app_log_message_body(line)

    case :binary.match(body, @prefix) do
      :nomatch ->
        nil

      {start, len} ->
        rest = binary_part(body, start + len, byte_size(body) - start - len)
        parse_pairs(rest)
    end
  end

  def parse(_), do: nil

  @spec parse_many([String.t()]) :: t() | nil
  def parse_many(lines) when is_list(lines) do
    Enum.reduce(lines, nil, fn line, acc ->
      case parse(line) do
        nil -> acc
        stats -> merge(acc, stats)
      end
    end)
  end

  @spec merge(t() | nil, t() | nil) :: t() | nil
  def merge(nil, next), do: next
  def merge(current, nil), do: current

  def merge(current, next) when is_map(current) and is_map(next) do
    %{
      scene_bytes: max(current.scene_bytes, next.scene_bytes),
      scene_cmds: max(current.scene_cmds, next.scene_cmds),
      scene_cap: max(current.scene_cap, next.scene_cap),
      heap_free: next.heap_free,
      heap_free_min:
        if current.heap_free_min > 0 do
          min(current.heap_free_min, next.heap_free_min)
        else
          next.heap_free_min
        end
    }
  end

  defp app_log_message_body(message) do
    case Regex.run(~r/AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/, message) do
      [_, body] -> body
      _ -> message
    end
  end

  defp parse_pairs(rest) do
    pairs =
      rest
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce(%{}, fn token, acc ->
        case String.split(token, "=", parts: 2) do
          [key, value] ->
            case Map.fetch(@key_atoms, key) do
              {:ok, atom} ->
                case Integer.parse(value) do
                  {int, _} -> Map.put(acc, atom, int)
                  :error -> acc
                end

              :error ->
                acc
            end

          _ ->
            acc
        end
      end)

    if Enum.all?(@required_keys, &Map.has_key?(pairs, &1)), do: pairs, else: nil
  end
end
