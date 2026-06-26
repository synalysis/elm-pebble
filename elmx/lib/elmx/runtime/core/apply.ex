defmodule Elmx.Runtime.Core.Apply do
  @moduledoc false

  alias Elmx.Types

  @typedoc "Elm-style callback (may be curried)."
  @type callback :: (Types.elm_value() -> Types.elm_value())

  @doc "Fixed-point combinator for let-rec bindings (`\\n -> ... n ...`)."
  @spec fix((Types.elm_hof() -> Types.elm_hof())) :: Types.elm_hof()
  def fix(f) when is_function(f, 1) do
    g = fn g -> f.(fn x -> g.(g).(x) end) end
    g.(g)
  end

  @doc """
  Apply an Elm-style unary callback; rejects still-curried results from partial application bugs.
  """
  @spec apply1(Types.elm_hof(), Types.elm_value()) :: Types.elm_value()
  def apply1(fun, arg) when is_function(fun, 2) do
    fn next -> fun.(arg, next) end
  end

  def apply1(fun, arg) when is_function(fun, 3) do
    fn b ->
      fn c -> fun.(arg, b, c) end
    end
  end

  def apply1(fun, arg) when is_function(fun, 1) do
    case fun.(arg) do
      step when is_function(step, 1) ->
        raise ArgumentError,
              "expected unary Elm callback result, got function still awaiting an argument"

      value ->
        value
    end
  end

  @doc "Apply the same unary callback `count` times, starting from `arg`."
  @spec repeat1(Types.elm_hof(), non_neg_integer(), Types.elm_value()) :: Types.elm_value()
  def repeat1(fun, count, arg) when is_integer(count) and count >= 0 do
    repeat1_loop(fun, count, arg)
  end

  defp repeat1_loop(_fun, 0, acc), do: acc

  defp repeat1_loop(fun, count, acc) when count > 0 do
    repeat1_loop(fun, count - 1, apply1(fun, acc))
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

  @spec apply5(Types.elm_hof(), Types.elm_value(), Types.elm_value(), Types.elm_value(), Types.elm_value(), Types.elm_value()) ::
          Types.elm_value()
  def apply5(fun, a, b, c, d, e) when is_function(fun, 5), do: fun.(a, b, c, d, e)

  def apply5(fun, a, b, c, d, e) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) ->
            case step2.(c) do
              step3 when is_function(step3, 1) ->
                case step3.(d) do
                  step4 when is_function(step4, 1) -> step4.(e)
                  other -> raise ArgumentError, "Core.Apply.apply5 expected curried step, got: #{inspect(other)}"
                end

              other ->
                raise ArgumentError, "Core.Apply.apply5 expected curried step, got: #{inspect(other)}"
            end

          other ->
            raise ArgumentError, "Core.Apply.apply5 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.Apply.apply5 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply6(Types.elm_hof(), Types.elm_value(), Types.elm_value(), Types.elm_value(), Types.elm_value(), Types.elm_value(), Types.elm_value()) ::
          Types.elm_value()
  def apply6(fun, a, b, c, d, e, f) when is_function(fun, 6), do: fun.(a, b, c, d, e, f)

  def apply6(fun, a, b, c, d, e, f) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) ->
            case step2.(c) do
              step3 when is_function(step3, 1) ->
                case step3.(d) do
                  step4 when is_function(step4, 1) ->
                    case step4.(e) do
                      step5 when is_function(step5, 1) -> step5.(f)
                      other -> raise ArgumentError, "Core.Apply.apply6 expected curried step, got: #{inspect(other)}"
                    end

                  other ->
                    raise ArgumentError, "Core.Apply.apply6 expected curried step, got: #{inspect(other)}"
                end

              other ->
                raise ArgumentError, "Core.Apply.apply6 expected curried step, got: #{inspect(other)}"
            end

          other ->
            raise ArgumentError, "Core.Apply.apply6 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.Apply.apply6 expected curried step, got: #{inspect(other)}"
    end
  end

  @spec apply7(
          Types.elm_hof(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value(),
          Types.elm_value()
        ) :: Types.elm_value()
  def apply7(fun, a, b, c, d, e, f, g) when is_function(fun, 7), do: fun.(a, b, c, d, e, f, g)

  def apply7(fun, a, b, c, d, e, f, g) when is_function(fun, 1) do
    case fun.(a) do
      step when is_function(step, 1) ->
        case step.(b) do
          step2 when is_function(step2, 1) ->
            case step2.(c) do
              step3 when is_function(step3, 1) ->
                case step3.(d) do
                  step4 when is_function(step4, 1) ->
                    case step4.(e) do
                      step5 when is_function(step5, 1) ->
                        case step5.(f) do
                          step6 when is_function(step6, 1) -> step6.(g)
                          other -> raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
                        end

                      other ->
                        raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
                    end

                  other ->
                    raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
                end

              other ->
                raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
            end

          other ->
            raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
        end

      other ->
        raise ArgumentError, "Core.Apply.apply7 expected curried step, got: #{inspect(other)}"
    end
  end
end
