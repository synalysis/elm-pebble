defmodule Ide.Debugger.StepDepth do
  @moduledoc false

  @key :debugger_apply_step_depth

  @spec enter() :: :ok
  def enter do
    Process.put(@key, depth() + 1)
    :ok
  end

  @spec leave() :: non_neg_integer()
  def leave do
    next = max(depth() - 1, 0)
    Process.put(@key, next)
    next
  end

  @spec depth() :: non_neg_integer()
  def depth, do: Process.get(@key, 0)

  @spec nested?() :: boolean()
  def nested?, do: depth() > 1
end
