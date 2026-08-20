defmodule Ide.ZipArchive do
  @moduledoc false

  @type zip_entry_info :: :file.file_info()
  @type zip_entry_comment :: charlist() | binary() | String.t()
  @type zip_dir_entry ::
          {:zip_file, charlist(), zip_entry_info(), zip_entry_comment(), non_neg_integer(),
           non_neg_integer()}
          | {:zip_comment, zip_entry_comment()}
  @type zip_memory_entry :: {charlist(), binary()}
  @type zip_read_error :: {:entry_not_found, String.t()}
  @type zip_error :: zip_read_error() | :bad_file | :badarg | atom()

  @spec list_files(String.t()) :: {:ok, [zip_dir_entry()]} | {:error, zip_error()}
  def list_files(archive_path) when is_binary(archive_path) do
    :zip.list_dir(String.to_charlist(archive_path))
  end

  @doc """
  File names from `:zip.list_dir/1` output. Skips archive comments and any
  non-file records so callers can safely scan entry names.
  """
  @spec file_names([term()]) :: [String.t()]
  def file_names(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      {:zip_file, name, _info, _comment, _offset, _size} ->
        [to_string(name)]

      {:zip_file, name, _info, _comment, _offset, _comp_size, _uncomp_size} ->
        [to_string(name)]

      _other ->
        []
    end)
  end

  @spec read_entry(String.t(), String.t()) :: {:ok, binary()} | {:error, zip_error()}
  def read_entry(archive_path, entry)
      when is_binary(archive_path) and is_binary(entry) do
    charlist_path = String.to_charlist(archive_path)

    case :zip.extract(charlist_path, [:memory]) do
      {:ok, files} ->
        case Enum.find(files, fn {name, _data} -> to_string(name) == entry end) do
          {_name, data} -> {:ok, data}
          nil -> {:error, {:entry_not_found, entry}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_all(String.t()) :: {:ok, [zip_memory_entry()]} | {:error, zip_error()}
  def extract_all(archive_path) when is_binary(archive_path) do
    :zip.extract(String.to_charlist(archive_path), [:memory])
  end
end
