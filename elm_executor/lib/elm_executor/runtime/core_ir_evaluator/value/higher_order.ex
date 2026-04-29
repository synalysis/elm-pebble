defmodule ElmExecutor.Runtime.CoreIREvaluator.Value.HigherOrder do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult
  alias ElmExecutor.Runtime.CoreIREvaluator.Value.String, as: StringValue

  @spec maybe_map_with_callable(term(), term(), function()) :: term()
  def maybe_map_with_callable(fun, maybe, call) when is_function(call, 2) do
    case MaybeResult.maybe_value(maybe) do
      {:just, value} ->
        case call.(fun, [value]) do
          {:ok, mapped} -> {:ok, MaybeResult.maybe_ctor_like(maybe, {:just, mapped})}
          {:error, reason} -> {:error, reason}
        end

      :nothing ->
        {:ok, MaybeResult.maybe_ctor_like(maybe, :nothing)}

      :invalid ->
        :no_builtin
    end
  end

  @spec maybe_map2_with_callable(term(), term(), term(), function()) :: term()
  def maybe_map2_with_callable(fun, a, b, call) when is_function(call, 2) do
    case {MaybeResult.maybe_value(a), MaybeResult.maybe_value(b)} do
      {{:just, av}, {:just, bv}} ->
        case call.(fun, [av, bv]) do
          {:ok, value} -> {:ok, MaybeResult.maybe_ctor_like(a, {:just, value})}
          {:error, reason} -> {:error, reason}
        end

      {:invalid, _} ->
        :no_builtin

      {_, :invalid} ->
        :no_builtin

      _ ->
        {:ok, MaybeResult.maybe_ctor_like(a, :nothing)}
    end
  end

  @spec result_map_with_callable(term(), term(), function()) :: term()
  def result_map_with_callable(fun, result, call) when is_function(call, 2) do
    case MaybeResult.result_value(result) do
      {:ok, value} ->
        case call.(fun, [value]) do
          {:ok, mapped} -> {:ok, MaybeResult.result_ctor_like(result, {:ok, mapped})}
          {:error, reason} -> {:error, reason}
        end

      {:err, error} ->
        {:ok, MaybeResult.result_ctor_like(result, {:err, error})}

      :invalid ->
        :no_builtin
    end
  end

  @spec result_map2_with_callable(term(), term(), term(), function()) :: term()
  def result_map2_with_callable(fun, a, b, call) when is_function(call, 2) do
    case {MaybeResult.result_value(a), MaybeResult.result_value(b)} do
      {{:ok, av}, {:ok, bv}} ->
        case call.(fun, [av, bv]) do
          {:ok, value} -> {:ok, MaybeResult.result_ctor_like(a, {:ok, value})}
          {:error, reason} -> {:error, reason}
        end

      {{:err, error}, _} ->
        {:ok, MaybeResult.result_ctor_like(a, {:err, error})}

      {_, {:err, error}} ->
        {:ok, MaybeResult.result_ctor_like(b, {:err, error})}

      _ ->
        :no_builtin
    end
  end

  @spec result_and_then_with_callable(term(), term(), function()) :: term()
  def result_and_then_with_callable(fun, result, call) when is_function(call, 2) do
    case MaybeResult.result_value(result) do
      {:ok, value} ->
        call.(fun, [value])

      {:err, error} ->
        {:ok, MaybeResult.result_ctor_like(result, {:err, error})}

      :invalid ->
        :no_builtin
    end
  end

  @spec string_map_with_callable(term(), term(), function()) :: term()
  def string_map_with_callable(fun, text, call) when is_function(call, 2) do
    text
    |> String.graphemes()
    |> Enum.map(fn ch -> call.(fun, [ch]) end)
    |> collect_ok()
    |> case do
      {:ok, chars} ->
        {:ok, chars |> Enum.map(&StringValue.normalize_char_binary/1) |> Enum.join()}

      err ->
        err
    end
  end

  @spec string_filter_with_callable(term(), term(), function()) :: term()
  def string_filter_with_callable(fun, text, call) when is_function(call, 2) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({:ok, []}, fn ch, {:ok, acc} ->
      case call.(fun, [ch]) do
        {:ok, true} -> {:cont, {:ok, [ch | acc]}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, chars} -> {:ok, chars |> Enum.reverse() |> Enum.join()}
      err -> err
    end
  end

  @spec string_all_with_callable(term(), term(), function()) :: term()
  def string_all_with_callable(fun, text, call),
    do: all_with_callable(fun, String.graphemes(text), call)

  @spec string_any_with_callable(term(), term(), function()) :: term()
  def string_any_with_callable(fun, text, call),
    do: any_with_callable(fun, String.graphemes(text), call)

  @spec string_foldl_with_callable(term(), term(), term(), function()) :: term()
  def string_foldl_with_callable(fun, init, text, call),
    do: foldl_with_callable(fun, init, String.graphemes(text), call)

  @spec string_foldr_with_callable(term(), term(), term(), function()) :: term()
  def string_foldr_with_callable(fun, init, text, call),
    do: foldr_with_callable(fun, init, String.graphemes(text), call)

  @spec all_with_callable(term(), list(), function()) :: term()
  defp all_with_callable(fun, xs, call) do
    Enum.reduce_while(xs, {:ok, true}, fn x, _acc ->
      case call.(fun, [x]) do
        {:ok, true} -> {:cont, {:ok, true}}
        {:ok, _} -> {:halt, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec any_with_callable(term(), list(), function()) :: term()
  defp any_with_callable(fun, xs, call) do
    Enum.reduce_while(xs, {:ok, false}, fn x, _acc ->
      case call.(fun, [x]) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, _} -> {:cont, {:ok, false}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec foldl_with_callable(term(), term(), list(), function()) :: term()
  defp foldl_with_callable(fun, init, xs, call) do
    Enum.reduce_while(xs, {:ok, init}, fn x, {:ok, acc} ->
      case call.(fun, [x, acc]) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec foldr_with_callable(term(), term(), list(), function()) :: term()
  defp foldr_with_callable(fun, init, xs, call) do
    xs
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, init}, fn x, {:ok, acc} ->
      case call.(fun, [x, acc]) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec collect_ok(list()) :: {:ok, list()} | {:error, term()}
  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
      other, _acc -> {:halt, {:error, {:unexpected_result, other}}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
