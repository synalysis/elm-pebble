defmodule Ide.TestSupport.EmulatorSessionEnv do
  @moduledoc false

  @lock {__MODULE__, :application_env}

  defp default_env do
    [
      enabled: true,
      validate_runtime: false,
      start_processes: false,
      qemu_image_root: System.tmp_dir!(),
      idle_timeout_ms: 60_000
    ]
  end

  @spec run((-> result)) :: result when result: var
  def run(fun) when is_function(fun, 0) do
    :global.trans(@lock, fn ->
      previous = Application.get_env(:ide, Ide.Emulator.Session)

      Application.put_env(:ide, Ide.Emulator.Session, default_env())

      try do
        fun.()
      after
        Application.put_env(:ide, Ide.Emulator.Session, previous)
      end
    end)
  end
end
