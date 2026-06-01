defmodule Elmx.CLI do
  @moduledoc false

  @spec main([String.t()]) :: :ok
  def main(argv) do
    case argv do
      ["check", project_dir] ->
        case Elmx.check(project_dir) do
          {:ok, _} -> :ok
          {:error, reason} -> halt_error(inspect(reason))
        end

      ["compile", project_dir, "--out", out_dir] ->
        case Elmx.compile(project_dir, %{out_dir: out_dir}) do
          {:ok, _} -> :ok
          {:error, reason} -> halt_error(inspect(reason))
        end

      _ ->
        IO.puts(:stderr, "usage: elmx check <project_dir> | elmx compile <project_dir> --out <dir>")
        System.halt(2)
    end
  end

  @spec halt_error(String.t()) :: no_return()
  defp halt_error(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
