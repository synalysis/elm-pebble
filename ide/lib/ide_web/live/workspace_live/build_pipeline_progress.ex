defmodule IdeWeb.WorkspaceLive.BuildPipelineProgress do
  @moduledoc false

  @step_count 5

  @type progress_event :: {pos_integer(), pos_integer(), String.t()} | String.t()
  @type progress :: (progress_event() -> :ok)

  @spec step_count() :: pos_integer()
  def step_count, do: @step_count

  @spec emit(progress(), pos_integer(), String.t()) :: :ok
  def emit(progress, step, message) when is_function(progress, 1) and is_binary(message) do
    progress.({step, @step_count, message})
  end

  def emit(_progress, _step, _message), do: :ok

  @spec step_segments(pos_integer() | nil, pos_integer() | nil) :: [
          %{index: pos_integer(), status: :done | :active | :pending}
        ]
  def step_segments(step, total) when is_integer(step) and is_integer(total) and total > 0 do
    1..total
    |> Enum.map(fn index ->
      status =
        cond do
          index < step -> :done
          index == step -> :active
          true -> :pending
        end

      %{index: index, status: status}
    end)
  end

  def step_segments(_step, _total), do: []
end
