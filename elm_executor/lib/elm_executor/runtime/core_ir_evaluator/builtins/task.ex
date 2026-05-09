defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Task do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("succeed", [value], _ops), do: {:ok, {:task, :ok, value}}
  def eval("fail", [error], _ops), do: {:ok, {:task, :err, error}}
  def eval("map", [fun, task], ops), do: ops.map.(fun, task)
  def eval("map2", [a, b, c], ops), do: ops.map2_dispatch.(a, b, c)
  def eval("map3", [fun, a, b, c], ops), do: map_n(fun, [a, b, c], ops)
  def eval("map4", [fun, a, b, c, d], ops), do: map_n(fun, [a, b, c, d], ops)
  def eval("map5", [fun, a, b, c, d, e], ops), do: map_n(fun, [a, b, c, d, e], ops)
  def eval("andthen", [fun, task], ops), do: task_and_then(fun, task, ops)
  def eval("onerror", [fun, task], ops), do: task_on_error(fun, task, ops)
  def eval("maperror", [fun, task], ops), do: task_map_error(fun, task, ops)
  def eval("sequence", [tasks], ops) when is_list(tasks), do: ops.sequence.(tasks)

  def eval("perform", [tagger, task], _ops),
    do: {:ok, %{"kind" => "cmd.task.perform", "tagger" => tagger, "task" => task}}

  def eval("attempt", [tagger, task], _ops),
    do: {:ok, %{"kind" => "cmd.task.attempt", "tagger" => tagger, "task" => task}}

  def eval(_function_name, _values, _ops), do: :no_builtin

  defp map_n(fun, tasks, ops) do
    case sequence_tasks(tasks) do
      {:ok, values} -> ops.call.(fun, values)
      {:err, error} -> {:ok, {:task, :err, error}}
      :invalid -> :no_builtin
    end
  end

  defp task_and_then(fun, {:task, :ok, value}, ops), do: ops.call.(fun, [value])
  defp task_and_then(_fun, {:task, :err, error}, _ops), do: {:ok, {:task, :err, error}}
  defp task_and_then(_fun, _task, _ops), do: :no_builtin

  defp task_on_error(_fun, {:task, :ok, value}, _ops), do: {:ok, {:task, :ok, value}}
  defp task_on_error(fun, {:task, :err, error}, ops), do: ops.call.(fun, [error])
  defp task_on_error(_fun, _task, _ops), do: :no_builtin

  defp task_map_error(_fun, {:task, :ok, value}, _ops), do: {:ok, {:task, :ok, value}}

  defp task_map_error(fun, {:task, :err, error}, ops) do
    case ops.call.(fun, [error]) do
      {:ok, mapped} -> {:ok, {:task, :err, mapped}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_map_error(_fun, _task, _ops), do: :no_builtin

  defp sequence_tasks(tasks) do
    Enum.reduce_while(tasks, {:ok, []}, fn
      {:task, :ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:task, :err, error}, _acc -> {:halt, {:err, error}}
      _other, _acc -> {:halt, :invalid}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end
end
