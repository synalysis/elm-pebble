defmodule ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @spec maybe_value(EvalTypes.runtime_value()) :: EvalTypes.maybe_parsed()
  def maybe_value(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, :args) || []
    short = short_ctor_name(to_string(ctor || ""))

    case {short, args} do
      {"Just", [inner]} -> {:just, inner}
      {"Nothing", _} -> :nothing
      _ -> :invalid
    end
  end

  def maybe_value({1, inner}), do: {:just, inner}
  def maybe_value(0), do: :nothing
  def maybe_value(_), do: :invalid

  @spec maybe_ctor(EvalTypes.maybe_ctor_input()) :: EvalTypes.ctor_map()
  def maybe_ctor({:just, value}), do: %{"ctor" => "Just", "args" => [value]}
  def maybe_ctor(:nothing), do: %{"ctor" => "Nothing", "args" => []}

  @spec maybe_ctor_like(EvalTypes.maybe_rep(), EvalTypes.maybe_ctor_input()) ::
          EvalTypes.runtime_value()
  def maybe_ctor_like(source, {:just, value}) when is_tuple(source), do: {1, value}
  def maybe_ctor_like(source, :nothing) when is_integer(source), do: 0
  def maybe_ctor_like(_source, parsed), do: maybe_ctor(parsed)

  @spec result_value(EvalTypes.runtime_value()) :: EvalTypes.result_parsed()
  def result_value(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, :args) || []
    short = short_ctor_name(to_string(ctor || ""))

    case {short, args} do
      {"Ok", [inner]} -> {:ok, inner}
      {"Err", [inner]} -> {:err, inner}
      _ -> :invalid
    end
  end

  def result_value({1, inner}), do: {:ok, inner}
  def result_value({0, inner}), do: {:err, inner}
  def result_value(_), do: :invalid

  @spec result_ctor(EvalTypes.result_ctor_input()) :: EvalTypes.ctor_map()
  def result_ctor({:ok, value}), do: %{"ctor" => "Ok", "args" => [value]}
  def result_ctor({:err, error}), do: %{"ctor" => "Err", "args" => [error]}

  @spec result_ctor_like(EvalTypes.result_rep(), EvalTypes.result_ctor_input()) ::
          EvalTypes.runtime_value()
  def result_ctor_like(source, {:ok, value}) when is_tuple(source), do: {1, value}
  def result_ctor_like(source, {:err, error}) when is_tuple(source), do: {0, error}
  def result_ctor_like(_source, parsed), do: result_ctor(parsed)

  @spec with_default(EvalTypes.runtime_value(), EvalTypes.runtime_value()) ::
          EvalTypes.runtime_value()
  def with_default(default, value) do
    case {maybe_value(value), result_value(value)} do
      {{:just, inner}, _} -> inner
      {:nothing, _} -> default
      {_, {:ok, inner}} -> inner
      {_, {:err, _}} -> default
      _ -> default
    end
  end

  @spec with_default_maybe_or_result(EvalTypes.runtime_value(), EvalTypes.runtime_value()) ::
          EvalTypes.runtime_value()
  def with_default_maybe_or_result(default, value), do: with_default(default, value)

  @spec head_ctor(list()) :: EvalTypes.ctor_map()
  def head_ctor([]), do: maybe_ctor(:nothing)
  def head_ctor([head | _]), do: maybe_ctor({:just, head})

  @spec maybe_head_ctor(list()) :: EvalTypes.ctor_map()
  def maybe_head_ctor(xs), do: head_ctor(xs)

  @spec tail_ctor(list()) :: EvalTypes.ctor_map()
  def tail_ctor([]), do: maybe_ctor(:nothing)
  def tail_ctor([_ | tail]), do: maybe_ctor({:just, tail})

  @spec maybe_tail_ctor(list()) :: EvalTypes.ctor_map()
  def maybe_tail_ctor(xs), do: tail_ctor(xs)

  @spec map_get_ctor(EvalTypes.dict_map(), EvalTypes.runtime_value()) :: EvalTypes.ctor_map()
  def map_get_ctor(dict, key) when is_map(dict) do
    if Map.has_key?(dict, key),
      do: maybe_ctor({:just, Map.get(dict, key)}),
      else: maybe_ctor(:nothing)
  end

  @spec maybe_map_get_ctor(EvalTypes.dict_map(), EvalTypes.runtime_value()) ::
          EvalTypes.ctor_map()
  def maybe_map_get_ctor(dict, key), do: map_get_ctor(dict, key)

  @spec extreme_ctor(list(), EvalTypes.extreme_kind()) :: EvalTypes.ctor_map()
  def extreme_ctor([], _kind), do: maybe_ctor(:nothing)
  def extreme_ctor(xs, :max), do: maybe_ctor({:just, Enum.max(xs)})
  def extreme_ctor(xs, :min), do: maybe_ctor({:just, Enum.min(xs)})

  @spec maybe_extreme_ctor(list(), EvalTypes.extreme_kind()) :: EvalTypes.ctor_map()
  def maybe_extreme_ctor(xs, kind), do: extreme_ctor(xs, kind)

  @spec short_ctor_name(EvalTypes.ctor_name()) :: String.t()
  defp short_ctor_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end
end
