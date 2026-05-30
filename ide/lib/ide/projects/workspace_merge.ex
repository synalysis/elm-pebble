defmodule Ide.Projects.WorkspaceMerge do
  @moduledoc """
  Non-destructive workspace tree copies.

  Merges files from a source directory into a destination without removing
  existing files that are absent from the source.
  """

  @type merge_error :: File.posix()

  @doc """
  Copies `source` into `target`, creating or overwriting matching paths only.
  """
  @spec merge_tree(String.t(), String.t()) :: :ok | {:error, merge_error()}
  def merge_tree(source, target) when is_binary(source) and is_binary(target) do
    cond do
      not File.dir?(source) ->
        {:error, :enoent}

      true ->
        :ok = File.mkdir_p(target)
        merge_entries(source, target)
    end
  end

  @spec merge_entries(String.t(), String.t()) :: :ok | {:error, merge_error()}
  defp merge_entries(source, target) do
    case File.ls(source) do
      {:ok, entries} ->
        Enum.reduce_while(entries, :ok, fn entry, :ok ->
          src = Path.join(source, entry)
          dst = Path.join(target, entry)

          result =
            if File.dir?(src) do
              :ok = File.mkdir_p(dst)
              merge_entries(src, dst)
            else
              :ok = File.mkdir_p(Path.dirname(dst))
              File.cp(src, dst)
            end

          case result do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
