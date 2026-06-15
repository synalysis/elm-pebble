defmodule Elmx.Runtime.Core.Task do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Types

  @type t :: Types.result_native()

  @spec succeed(Types.elm_value()) :: Types.result_native()
  def succeed(value), do: {:Ok, value}

  @spec fail(Types.elm_value()) :: Types.result_native()
  def fail(error), do: {:Err, error}

  @spec map(Types.elm_hof(), Types.result_like()) :: Types.result_native()
  def map(fun, task) when is_function(fun, 1) do
    case normalize(task) do
      {:ok, value} -> {:Ok, fun.(value)}
      {:error, reason} -> {:Err, reason}
    end
  end

  @spec and_then(Types.elm_hof(), Types.result_like()) :: Types.result_native()
  def and_then(fun, task) when is_function(fun, 1) do
    case normalize(task) do
      {:ok, value} ->
        case normalize(fun.(value)) do
          {:ok, next} -> {:Ok, next}
          {:error, reason} -> {:Err, reason}
        end

      {:error, reason} ->
        {:Err, reason}
    end
  end

  @spec map2(Types.elm_hof(), Types.result_like(), Types.result_like()) ::
          Types.result_native()
  def map2(fun, task_a, task_b) when is_function(fun, 2) do
    case {normalize(task_a), normalize(task_b)} do
      {{:ok, a}, {:ok, b}} -> {:Ok, fun.(a, b)}
      {{:error, reason}, _} -> {:Err, reason}
      {_, {:error, reason}} -> {:Err, reason}
    end
  end

  @spec perform(Types.elm_hof(), Types.result_like()) :: Types.wire_cmd()
  def perform(to_msg, task) when is_function(to_msg) do
    case normalize(task) do
      {:ok, value} -> Cmd.task_immediate(apply_to_msg(to_msg, value))
      {:error, _} -> Cmd.none()
    end
  end

  defp normalize({:Ok, value}), do: {:ok, value}
  defp normalize({:Err, reason}), do: {:error, reason}
  defp normalize(%{"ctor" => "Ok", "args" => [value]}), do: {:ok, value}
  defp normalize(%{"ctor" => "Err", "args" => [reason]}), do: {:error, reason}
  defp normalize(_), do: {:error, :bad_task}

  defp apply_to_msg(fun, {a, b}) when is_function(fun, 2), do: fun.(a, b)
  defp apply_to_msg(fun, [a, b]) when is_function(fun, 2), do: fun.(a, b)
  defp apply_to_msg(fun, value) when is_function(fun, 1), do: fun.(value)
  defp apply_to_msg(fun, value), do: fun.(value)
end
