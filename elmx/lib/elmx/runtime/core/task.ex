defmodule Elmx.Runtime.Core.Task do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Types

  @type t :: Types.task_native()

  @spec succeed(Types.elm_value()) :: Types.task_native()
  def succeed(value), do: {:elmx_task, :succeed, value}

  @spec fail(Types.elm_value()) :: Types.task_native()
  def fail(error), do: {:elmx_task, :fail, error}

  @spec map(Types.elm_hof(), Types.result_like()) :: Types.task_native() | Types.result_native()
  def map(fun, task) when is_function(fun, 1) do
    case task do
      {:Ok, value} ->
        {:Ok, fun.(value)}

      {:Err, reason} ->
        {:Err, reason}

      {:elmx_task, :succeed, value} ->
        {:elmx_task, :succeed, fun.(value)}

      {:elmx_task, :fail, reason} ->
        {:elmx_task, :fail, reason}

      other ->
        {:elmx_task, :map, {fun, other}}
    end
  end

  @spec and_then(Types.elm_hof(), Types.result_like()) :: Types.task_native() | Types.result_native()
  def and_then(fun, task) when is_function(fun, 1) do
    case task do
      {:Ok, value} ->
        normalize_and_then_result(fun.(value))

      {:Err, reason} ->
        {:Err, reason}

      {:elmx_task, :succeed, value} ->
        {:elmx_task, :and_then, {fun, {:elmx_task, :succeed, value}}}

      {:elmx_task, :fail, reason} ->
        {:elmx_task, :fail, reason}

      other ->
        {:elmx_task, :and_then, {fun, other}}
    end
  end

  @doc """
  Synchronously resolve opaque task values for `case`/`perform` paths.
  Non-task values pass through unchanged.
  """
  @spec force(Types.result_like() | term()) :: Types.result_native() | term()
  def force({:elmx_task, :spawn, _inner}), do: {:Ok, Elmx.Runtime.Core.Process.spawn_pid()}

  def force({:elmx_task, :succeed, value}), do: {:Ok, value}
  def force({:elmx_task, :fail, error}), do: {:Err, error}

  def force({:elmx_task, :map, {fun, task}}) when is_function(fun, 1) do
    case force(task) do
      {:Ok, value} -> {:Ok, fun.(value)}
      {:Err, reason} -> {:Err, reason}
    end
  end

  def force({:elmx_task, :and_then, {fun, task}}) when is_function(fun, 1) do
    case force(task) do
      {:Ok, value} -> normalize_and_then_result(fun.(value))
      {:Err, reason} -> {:Err, reason}
    end
  end

  def force({:Ok, _} = ok), do: ok
  def force({:Err, _} = err), do: err
  def force(other), do: other

  defp normalize_and_then_result({:Ok, value}), do: {:Ok, value}
  defp normalize_and_then_result({:Err, reason}), do: {:Err, reason}
  defp normalize_and_then_result(%{"ctor" => "Ok", "args" => [value]}), do: {:Ok, value}
  defp normalize_and_then_result(%{"ctor" => "Err", "args" => [reason]}), do: {:Err, reason}
  defp normalize_and_then_result({:elmx_task, _, _} = task), do: force(task)
  defp normalize_and_then_result(other), do: {:Err, {:bad_task, other}}

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

  defp normalize({:elmx_task, _kind, _payload}), do: {:error, :opaque_task}

  defp normalize({:Ok, value}), do: {:ok, value}
  defp normalize({:Err, reason}), do: {:error, reason}
  defp normalize(%{"ctor" => "Ok", "args" => [value]}), do: {:ok, value}
  defp normalize(%{"ctor" => "Err", "args" => [reason]}), do: {:error, reason}
  defp normalize(_), do: {:error, :bad_task}

  defp apply_to_msg(fun, {a, b}) when is_function(fun, 2), do: fun.(a, b)
  defp apply_to_msg(fun, [a, b]) when is_function(fun, 2), do: fun.(a, b)
  defp apply_to_msg(fun, value) when is_function(fun, 1), do: fun.(value)
  defp apply_to_msg(_fun, _value), do: nil
end
