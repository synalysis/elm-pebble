defmodule Elmx.Runtime.Core.MaybeResult do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Types

  @spec maybe_with_default(default, Types.maybe_like()) :: default when default: term
  def maybe_with_default(default, maybe) do
    case maybe do
      :Nothing -> default
      {:Just, value} -> value
      %{"ctor" => "Nothing"} -> default
      %{"ctor" => "Just", "args" => [value]} -> value
      %{ctor: :Nothing} -> default
      %{ctor: :Just, args: [value]} -> value
      %{"ctor" => "Err"} -> default
      {:Err, _} -> default
      nil -> default
      other -> other
    end
  end

  @spec maybe_map(Types.elm_hof(), Types.maybe_like()) :: Types.maybe_like()
  def maybe_map(_f, :Nothing), do: :Nothing
  def maybe_map(_f, %{"ctor" => "Nothing"}), do: :Nothing
  def maybe_map(_f, %{ctor: :Nothing}), do: :Nothing

  def maybe_map(f, {:Just, value}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(f, %{"ctor" => "Just", "args" => [value]}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(f, %{ctor: :Just, args: [value]}) when is_function(f, 1), do: {:Just, f.(value)}
  def maybe_map(_f, other), do: other

  @spec maybe_and_then(Types.elm_hof(), Types.maybe_like()) :: Types.maybe_like()
  def maybe_and_then(_f, :Nothing), do: :Nothing
  def maybe_and_then(_f, %{"ctor" => "Nothing"}), do: :Nothing
  def maybe_and_then(_f, %{ctor: :Nothing}), do: :Nothing

  def maybe_and_then(f, {:Just, value}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(f, %{"ctor" => "Just", "args" => [value]}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(f, %{ctor: :Just, args: [value]}) when is_function(f, 1), do: f.(value)
  def maybe_and_then(_f, other), do: other

  @spec maybe_map2(Types.maybe_like(), Types.maybe_like(), Types.elm_hof()) ::
          Types.maybe_like()
  def maybe_map2(maybe_a, maybe_b, f) when is_function(f, 2) do
    with {:Just, a} <- normalize_maybe_strict(maybe_a),
         {:Just, b} <- normalize_maybe_strict(maybe_b) do
      {:Just, f.(a, b)}
    else
      _ -> :Nothing
    end
  end

  def maybe_map2(maybe_a, maybe_b, f) when is_function(f, 1) do
    with {:Just, a} <- normalize_maybe_strict(maybe_a),
         {:Just, b} <- normalize_maybe_strict(maybe_b),
         inner when is_function(inner, 1) <- f.(a) do
      {:Just, inner.(b)}
    else
      _ -> :Nothing
    end
  end

  def maybe_map2(_maybe_a, _maybe_b, _f), do: :Nothing

  @spec maybe_map3(Types.elm_hof(), Types.maybe_like(), Types.maybe_like(), Types.maybe_like()) ::
          Types.maybe_like()
  def maybe_map3(fun, ma, mb, mc), do: maybe_map_n(fun, [ma, mb, mc])

  @spec maybe_map4(
          Types.elm_hof(),
          Types.maybe_like(),
          Types.maybe_like(),
          Types.maybe_like(),
          Types.maybe_like()
        ) :: Types.maybe_like()
  def maybe_map4(fun, ma, mb, mc, md), do: maybe_map_n(fun, [ma, mb, mc, md])

  @spec maybe_map5(
          Types.elm_hof(),
          Types.maybe_like(),
          Types.maybe_like(),
          Types.maybe_like(),
          Types.maybe_like(),
          Types.maybe_like()
        ) :: Types.maybe_like()
  def maybe_map5(fun, ma, mb, mc, md, me), do: maybe_map_n(fun, [ma, mb, mc, md, me])

  @spec result_map2(Types.elm_hof(), Types.result_like(), Types.result_like()) ::
          Types.result_like()
  def result_map2(fun, ra, rb), do: result_map_n(fun, [ra, rb])

  @spec result_map3(
          Types.elm_hof(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like()
        ) :: Types.result_like()
  def result_map3(fun, ra, rb, rc), do: result_map_n(fun, [ra, rb, rc])

  @spec result_map4(
          Types.elm_hof(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like()
        ) :: Types.result_like()
  def result_map4(fun, ra, rb, rc, rd), do: result_map_n(fun, [ra, rb, rc, rd])

  @spec result_map5(
          Types.elm_hof(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like(),
          Types.result_like()
        ) :: Types.result_like()
  def result_map5(fun, ra, rb, rc, rd, re), do: result_map_n(fun, [ra, rb, rc, rd, re])

  @spec result_map(Types.elm_hof(), Types.result_like()) :: Types.result_like()
  def result_map(_f, {:Err, _} = err), do: err
  def result_map(_f, %{"ctor" => "Err"} = err), do: err
  def result_map(f, {:Ok, value}) do
    {:Ok, Core.apply1(f, value)}
  end

  def result_map(f, %{"ctor" => "Ok", "args" => [value]}) do
    {:Ok, Core.apply1(f, value)}
  end
  def result_map(_f, other), do: other

  @spec result_and_then(Types.elm_hof(), Types.result_like()) :: Types.result_like()
  def result_and_then(_f, {:Err, _} = err), do: err
  def result_and_then(_f, %{"ctor" => "Err"} = err), do: err
  def result_and_then(f, {:Ok, value}) when is_function(f, 1), do: f.(value)
  def result_and_then(f, %{"ctor" => "Ok", "args" => [value]}) when is_function(f, 1), do: f.(value)
  def result_and_then(_f, other), do: other

  @spec result_map_error(Types.elm_hof(), Types.result_like()) :: Types.result_like()
  def result_map_error(f, {:Err, err}) when is_function(f, 1), do: {:Err, f.(err)}
  def result_map_error(f, %{"ctor" => "Err", "args" => [err]}) when is_function(f, 1), do: {:Err, f.(err)}
  def result_map_error(_f, {:Ok, _} = ok), do: ok
  def result_map_error(_f, %{"ctor" => "Ok"} = ok), do: ok
  def result_map_error(_f, other), do: other

  @spec result_with_default(default, Types.result_like()) :: default when default: term
  def result_with_default(default, result) do
    case result do
      {:Ok, value} -> value
      %{"ctor" => "Ok", "args" => [value]} -> value
      _ -> default
    end
  end

  @spec result_to_maybe(Types.result_like()) :: Types.maybe_like()
  def result_to_maybe({:Ok, value}), do: {:Just, value}
  def result_to_maybe(%{"ctor" => "Ok", "args" => [value]}), do: {:Just, value}
  def result_to_maybe(_), do: :Nothing

  @spec result_from_maybe(Types.elm_value(), Types.maybe_like()) :: Types.result_like()
  def result_from_maybe(err, maybe) do
    case maybe do
      {:Just, value} -> {:Ok, value}
      %{"ctor" => "Just", "args" => [value]} -> {:Ok, value}
      _ -> {:Err, err}
    end
  end

  @spec random_generator(integer(), integer()) :: Types.random_generator()
  def random_generator(low, high) when is_integer(low) and is_integer(high) do
    %{low: low, high: high}
  end

  @spec random_int(Types.random_generator() | %{optional(String.t()) => integer()}) :: integer()
  def random_int(%{low: low, high: high}) when is_integer(low) and is_integer(high) do
    case corpus_fixed_random_int() do
      n when is_integer(n) -> clamp_int(n, low, high)
      _ -> low + rem(:rand.uniform(max(high - low + 1, 1)), max(high - low + 1, 1))
    end
  end

  def random_int(%{"low" => low, "high" => high}), do: random_int(%{low: low, high: high})

  defp corpus_fixed_random_int do
    Process.get(:elmx_corpus_fixed_random_int) ||
      Application.get_env(:elmx, :corpus_fixed_random_int)
  end

  defp clamp_int(n, low, high) when is_integer(n) and is_integer(low) and is_integer(high) do
    min(max(n, low), high)
  end

  defp normalize_maybe_strict(:Nothing), do: :Nothing
  defp normalize_maybe_strict({:Just, value}), do: {:Just, value}
  defp normalize_maybe_strict(%{"ctor" => "Nothing"}), do: :Nothing
  defp normalize_maybe_strict(%{"ctor" => "Just", "args" => [value]}), do: {:Just, value}
  defp normalize_maybe_strict(%{ctor: :Nothing}), do: :Nothing
  defp normalize_maybe_strict(%{ctor: :Just, args: [value]}), do: {:Just, value}
  defp normalize_maybe_strict(_), do: :Nothing

  defp maybe_map_n(fun, maybes) do
    case collect_maybe_values(maybes) do
      :nothing -> :Nothing
      values -> {:Just, apply(fun, values)}
    end
  end

  defp collect_maybe_values(maybes) do
    Enum.reduce_while(maybes, [], fn maybe, acc ->
      case normalize_maybe_strict(maybe) do
        {:Just, value} -> {:cont, acc ++ [value]}
        :Nothing -> {:halt, :nothing}
      end
    end)
  end

  defp result_map_n(fun, results) do
    case collect_result_values(results) do
      {:error, err} -> {:Err, err}
      values -> {:Ok, apply(fun, values)}
    end
  end

  defp collect_result_values(results) do
    Enum.reduce_while(results, [], fn result, acc ->
      case normalize_result_strict(result) do
        {:ok, value} -> {:cont, acc ++ [value]}
        {:error, err} -> {:halt, {:error, err}}
      end
    end)
  end

  defp normalize_result_strict({:Ok, value}), do: {:ok, value}
  defp normalize_result_strict(%{"ctor" => "Ok", "args" => [value]}), do: {:ok, value}
  defp normalize_result_strict({:Err, err}), do: {:error, err}
  defp normalize_result_strict(%{"ctor" => "Err", "args" => [err]}), do: {:error, err}
  defp normalize_result_strict(_), do: {:error, :bad_result}
end
