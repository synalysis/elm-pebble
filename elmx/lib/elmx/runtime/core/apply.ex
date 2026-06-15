defmodule Elmx.Runtime.Core.Apply do
  @moduledoc false

  alias Elmx.Types

  @typedoc "Elm-style callback (may be curried)."
  @type callback :: (Types.elm_value() -> Types.elm_value())

  @doc """
  Apply an Elm-style unary callback; rejects still-curried results from partial application bugs.
  """
  @spec apply1(Types.elm_hof(), Types.elm_value()) :: Types.elm_value()
  def apply1(fun, arg) when is_function(fun, 1) do
    case fun.(arg) do
      step when is_function(step, 1) ->
        raise ArgumentError,
              "expected unary Elm callback result, got function still awaiting an argument"

      value ->
        value
    end
  end

  @doc """
  Apply an Elm-style function that may be 2-arity or curried `\\a -> \\b ->`.
  """
  @spec apply2(Types.elm_hof(), Types.elm_value(), Types.elm_value()) :: Types.elm_value()
  def apply2(fun, a, b) when is_function(fun, 2), do: fun.(a, b)

  def apply2(fun, a, b) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) -> step.(b)
      other -> raise ArgumentError, "Core.Apply.apply2 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply3(Types.elm_hof(), Types.elm_value(), Types.elm_value(), Types.elm_value()) ::
          Types.elm_value()
  def apply3(fun, a, b, c) when is_function(fun, 3), do: fun.(a, b, c)

  def apply3(fun, a, b, c) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) -> step2.(c)
          other -> raise ArgumentError, "Core.Apply.apply3 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.Apply.apply3 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply4(
          Types.elm_hof(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value()
        ) :: Types.elm_value()
  def apply4(fun, a, b, c, d) when is_function(fun, 4), do: fun.(a, b, c, d)

  def apply4(fun, a, b, c, d) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) ->
            case step2.(c) do
              step3 when is_function(step3, 1) -> step3.(d)
              other -> raise ArgumentError, "Core.Apply.apply4 expected curried step, got: #{inspect(other)}"
            end

          other ->
            raise ArgumentError, "Core.Apply.apply4 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.Apply.apply4 expected curried step, got: #{inspect(other)}"
    end
  end
end
