defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Dict do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.Dict, as: DictValue
  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("empty", [], _ops), do: {:ok, %{}}
  def eval("singleton", [key, value], _ops), do: {:ok, %{key => value}}

  def eval("fromlist", [pairs], _ops) when is_list(pairs),
    do: {:ok, DictValue.dict_from_pair_list(pairs)}

  def eval("tolist", [dict], _ops) when is_map(dict), do: {:ok, DictValue.dict_to_list(dict)}
  def eval("keys", [dict], _ops) when is_map(dict), do: {:ok, DictValue.dict_keys(dict)}
  def eval("values", [dict], _ops) when is_map(dict), do: {:ok, DictValue.dict_values(dict)}
  def eval("size", [dict], _ops) when is_map(dict), do: {:ok, map_size(dict)}
  def eval("isempty", [dict], _ops) when is_map(dict), do: {:ok, map_size(dict) == 0}
  def eval("member", [key, dict], _ops) when is_map(dict), do: {:ok, Map.has_key?(dict, key)}

  def eval("get", [key, dict], _ops) when is_map(dict),
    do: {:ok, MaybeResult.maybe_map_get_ctor(dict, key)}

  def eval("insert", [key, value, dict], _ops) when is_map(dict),
    do: {:ok, Map.put(dict, key, value)}

  def eval("remove", [key, dict], _ops) when is_map(dict), do: {:ok, Map.delete(dict, key)}

  def eval("update", [key, fun, dict], ops) when is_map(dict),
    do: update_dict(key, fun, dict, ops)

  def eval("map", [fun, dict], ops) when is_map(dict), do: map_dict(fun, dict, ops)

  def eval("foldl", [fun, init, dict], ops) when is_map(dict),
    do: fold_dict(fun, init, dict, ops, :asc)

  def eval("foldr", [fun, init, dict], ops) when is_map(dict),
    do: fold_dict(fun, init, dict, ops, :desc)

  def eval("filter", [fun, dict], ops) when is_map(dict), do: filter_dict(fun, dict, ops)
  def eval("partition", [fun, dict], ops) when is_map(dict), do: partition_dict(fun, dict, ops)

  def eval("union", [left, right], _ops) when is_map(left) and is_map(right),
    do: {:ok, Map.merge(right, left)}

  def eval("intersect", [left, right], _ops) when is_map(left) and is_map(right),
    do: {:ok, Map.take(left, Map.keys(right))}

  def eval("diff", [left, right], _ops) when is_map(left) and is_map(right),
    do: {:ok, Map.drop(left, Map.keys(right))}

  def eval("merge", [left_step, both_step, right_step, left, right, result], ops)
      when is_map(left) and is_map(right),
      do: merge_dict(left_step, both_step, right_step, left, right, result, ops)

  def eval(_function_name, _values, _ops), do: :no_builtin

  defp update_dict(key, fun, dict, ops) do
    current = MaybeResult.maybe_map_get_ctor(dict, key)

    case ops.call.(fun, [current]) do
      {:ok, maybe} ->
        case MaybeResult.maybe_value(maybe) do
          {:just, value} -> {:ok, Map.put(dict, key, value)}
          :nothing -> {:ok, Map.delete(dict, key)}
          :invalid -> :no_builtin
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp map_dict(fun, dict, ops) do
    dict
    |> DictValue.dict_to_list()
    |> Enum.map(fn {key, value} ->
      case ops.call.(fun, [key, value]) do
        {:ok, mapped} -> {:ok, {key, mapped}}
        error -> error
      end
    end)
    |> collect_ok()
    |> case do
      {:ok, pairs} -> {:ok, Map.new(pairs)}
      error -> error
    end
  end

  defp fold_dict(fun, init, dict, ops, order) do
    pairs = DictValue.dict_to_list(dict)
    pairs = if order == :desc, do: Enum.reverse(pairs), else: pairs

    Enum.reduce_while(pairs, {:ok, init}, fn {key, value}, {:ok, acc} ->
      case ops.call.(fun, [key, value, acc]) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp filter_dict(fun, dict, ops) do
    dict
    |> DictValue.dict_to_list()
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case ops.call.(fun, [key, value]) do
        {:ok, true} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp partition_dict(fun, dict, ops) do
    dict
    |> DictValue.dict_to_list()
    |> Enum.reduce_while({:ok, {%{}, %{}}}, fn {key, value}, {:ok, {yes, no}} ->
      case ops.call.(fun, [key, value]) do
        {:ok, true} -> {:cont, {:ok, {Map.put(yes, key, value), no}}}
        {:ok, _} -> {:cont, {:ok, {yes, Map.put(no, key, value)}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp merge_dict(left_step, both_step, right_step, left, right, result, ops) do
    keys = (Map.keys(left) ++ Map.keys(right)) |> Enum.uniq() |> Enum.sort()

    Enum.reduce_while(keys, {:ok, result}, fn key, {:ok, acc} ->
      cond do
        Map.has_key?(left, key) and Map.has_key?(right, key) ->
          step_dict_merge(
            both_step,
            [key, Map.fetch!(left, key), Map.fetch!(right, key), acc],
            ops
          )

        Map.has_key?(left, key) ->
          step_dict_merge(left_step, [key, Map.fetch!(left, key), acc], ops)

        true ->
          step_dict_merge(right_step, [key, Map.fetch!(right, key), acc], ops)
      end
    end)
  end

  defp step_dict_merge(fun, args, ops) do
    case ops.call.(fun, args) do
      {:ok, next} -> {:cont, {:ok, next}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
