defmodule Ide.ZipArchiveTest do
  use ExUnit.Case, async: true

  alias Ide.ZipArchive

  test "file_names skips zip comments and unknown records" do
    assert ZipArchive.file_names([
             {:zip_comment, ~c"pebble"},
             {:zip_file, ~c"appinfo.json", :file_info, ~c"", 0, 12},
             {:zip_file, ~c"manifest.json", :file_info, ~c"", 0, 8, 8},
             :not_a_zip_entry
           ]) == ["appinfo.json", "manifest.json"]
  end

  test "list_files on a real archive includes a comment record without hiding files" do
    path =
      Path.join(
        System.tmp_dir!(),
        "ide_zip_archive_test_#{System.unique_integer([:positive])}.zip"
      )

    on_exit(fn -> File.rm(path) end)

    {:ok, {_name, binary}} =
      :zip.create(~c"archive.zip", [{~c"appinfo.json", "{}"}], [:memory])

    File.write!(path, binary)

    assert {:ok, entries} = ZipArchive.list_files(path)
    assert {:zip_comment, _} = Enum.find(entries, &match?({:zip_comment, _}, &1))
    assert "appinfo.json" in ZipArchive.file_names(entries)
  end
end
