defmodule Elmx.Runtime.Core do
  @moduledoc """
  Elm `elm/core` runtime helpers for generated Elixir code.
  """

  alias Elmx.Types

  # Maybe/Result/random helpers live in `Elmx.Runtime.Core.MaybeResult`.
  defdelegate maybe_with_default(default, maybe), to: Elmx.Runtime.Core.MaybeResult
  defdelegate maybe_map(f, maybe), to: Elmx.Runtime.Core.MaybeResult
  defdelegate maybe_and_then(f, maybe), to: Elmx.Runtime.Core.MaybeResult
  defdelegate maybe_map2(a, b, f), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_map(f, result), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_and_then(f, result), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_map_error(f, result), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_with_default(default, result), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_to_maybe(result), to: Elmx.Runtime.Core.MaybeResult
  defdelegate result_from_maybe(err, maybe), to: Elmx.Runtime.Core.MaybeResult
  defdelegate random_generator(low, high), to: Elmx.Runtime.Core.MaybeResult
  defdelegate random_int(generator), to: Elmx.Runtime.Core.MaybeResult

  @spec basics_not(boolean()) :: boolean()
  def basics_not(value) when is_boolean(value), do: not value
  def basics_not(value), do: !value

  @spec basics_negate(number()) :: number()
  def basics_negate(n) when is_number(n), do: -n
  def basics_negate(_), do: 0

  @spec basics_abs(number()) :: number()
  def basics_abs(n) when is_number(n), do: abs(n)
  def basics_abs(_), do: 0

  @spec basics_max(Types.comparable(), Types.comparable()) :: Types.comparable()
  def basics_max(a, b), do: max(a, b)

  @spec basics_min(Types.comparable(), Types.comparable()) :: Types.comparable()
  def basics_min(a, b), do: min(a, b)

  @spec basics_mod_by(integer(), integer()) :: integer()
  def basics_mod_by(base, value) when is_integer(base) and base != 0, do: Integer.mod(value, base)
  def basics_mod_by(_base, _value), do: 0

  @spec basics_clamp(Types.comparable(), Types.comparable(), Types.comparable()) ::
          Types.comparable()
  def basics_clamp(low, high, value), do: max(low, min(high, value))

  @spec new_char(integer()) :: binary()
  def new_char(code) when is_integer(code), do: <<code::utf8>>
  def new_char(_), do: ""

  @spec basics_compare(Types.comparable(), Types.comparable()) :: -1 | 0 | 1
  def basics_compare(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  def basics_compare(a, b) when is_number(a) and is_number(b) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  def basics_compare(a, b) do
    case {to_number(a), to_number(b)} do
      {{:ok, na}, {:ok, nb}} -> basics_compare(na, nb)
      _ -> 0
    end
  end

  @doc """
  Elm `++` for strings and lists (debugger runtime).
  """
  @spec append(Types.elm_list() | String.t(), Types.elm_list() | String.t()) ::
          Types.elm_list() | String.t()
  def append(left, right) when is_list(left) and is_list(right), do: left ++ right
  def append(left, right), do: to_string(left) <> to_string(right)

  @spec apply1(Types.elm_hof(), Types.elm_value()) :: Types.elm_value()
  defdelegate apply1(fun, arg), to: Elmx.Runtime.Core.Apply

  @spec apply2(Types.elm_hof(), Types.elm_value(), Types.elm_value()) :: Types.elm_value()
  defdelegate apply2(fun, a, b), to: Elmx.Runtime.Core.Apply

  @spec apply3(Types.elm_hof(), Types.elm_value(), Types.elm_value(), Types.elm_value()) ::
          Types.elm_value()
  defdelegate apply3(fun, a, b, c), to: Elmx.Runtime.Core.Apply

  @spec apply4(
          Types.elm_hof(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value()
        ) :: Types.elm_value()
  defdelegate apply4(fun, a, b, c, d), to: Elmx.Runtime.Core.Apply

  defp to_number(n) when is_integer(n), do: {:ok, n}
  defp to_number(n) when is_float(n), do: {:ok, n}
  defp to_number(%{"ctor" => "Float", "args" => [f]}), do: {:ok, f * 1.0}
  defp to_number(%{ctor: :Float, args: [f]}), do: {:ok, f * 1.0}
  defp to_number(_), do: :error

  # List helpers live in `Elmx.Runtime.Core.List`.
  defdelegate list_head(list), to: Elmx.Runtime.Core.List
  defdelegate list_tail(list), to: Elmx.Runtime.Core.List
  defdelegate list_length(list), to: Elmx.Runtime.Core.List
  defdelegate list_is_empty(list), to: Elmx.Runtime.Core.List
  defdelegate list_reverse(list), to: Elmx.Runtime.Core.List
  defdelegate list_append(left, right), to: Elmx.Runtime.Core.List
  defdelegate list_concat(lists), to: Elmx.Runtime.Core.List
  defdelegate list_cons(head, tail), to: Elmx.Runtime.Core.List
  defdelegate list_singleton(value), to: Elmx.Runtime.Core.List
  defdelegate list_range(lo, hi), to: Elmx.Runtime.Core.List
  defdelegate list_take(n, list), to: Elmx.Runtime.Core.List
  defdelegate list_drop(n, list), to: Elmx.Runtime.Core.List
  defdelegate list_partition(fun, list), to: Elmx.Runtime.Core.List
  defdelegate list_unzip(list), to: Elmx.Runtime.Core.List
  defdelegate list_intersperse(sep, list), to: Elmx.Runtime.Core.List
  defdelegate list_map2(fun, as, bs), to: Elmx.Runtime.Core.List
  defdelegate list_map3(fun, as, bs, cs), to: Elmx.Runtime.Core.List
  defdelegate list_repeat(n, value), to: Elmx.Runtime.Core.List
  defdelegate map(fun, list), to: Elmx.Runtime.Core.List
  defdelegate filter(fun, list), to: Elmx.Runtime.Core.List
  defdelegate any(fun, list), to: Elmx.Runtime.Core.List
  defdelegate filter_map(fun, list), to: Elmx.Runtime.Core.List
  defdelegate concat_map(fun, list), to: Elmx.Runtime.Core.List
  defdelegate sort_by(fun, list), to: Elmx.Runtime.Core.List
  defdelegate foldl(fun, acc, list), to: Elmx.Runtime.Core.List
  defdelegate foldr(fun, acc, list), to: Elmx.Runtime.Core.List
  defdelegate member(value, list), to: Elmx.Runtime.Core.List
  defdelegate all(fun, list), to: Elmx.Runtime.Core.List
  defdelegate sort(list), to: Elmx.Runtime.Core.List
  defdelegate list_product(list), to: Elmx.Runtime.Core.List
  defdelegate list_maximum(list), to: Elmx.Runtime.Core.List
  defdelegate list_minimum(list), to: Elmx.Runtime.Core.List
  defdelegate list_sum(list), to: Elmx.Runtime.Core.List
  defdelegate sort_with(fun, list), to: Elmx.Runtime.Core.List
  defdelegate indexed_map(fun, list), to: Elmx.Runtime.Core.List
end
