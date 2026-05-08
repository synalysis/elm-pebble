defmodule Ide.TestSupport.EmulatorLaunch do
  @moduledoc false

  alias Ide.Emulator

  @max_attempts 8
  @initial_delay_ms 25

  @spec launch(Ide.Emulator.launch_opts()) :: {:ok, map()} | {:error, term()}
  def launch(opts) when is_list(opts) do
    do_launch(opts, @max_attempts, @initial_delay_ms)
  end

  defp try_launch_rescue(opts) do
    Emulator.launch(opts)
  catch
    :exit, reason ->
      {:error, {:exit, reason}}
  end

  defp do_launch(opts, 1, _delay_ms), do: Emulator.launch(opts)

  defp do_launch(opts, attempts_left, delay_ms) do
    case try_launch_rescue(opts) do
      {:ok, info} ->
        {:ok, info}

      {:error, _} ->
        Process.sleep(delay_ms)
        do_launch(opts, attempts_left - 1, min(delay_ms * 2, 200))
    end
  end
end
