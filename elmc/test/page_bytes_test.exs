defmodule Elmc.PageBytesTest do
  use ExUnit.Case, async: true

  @self_test Path.expand("support/page_bytes_self_test.mjs", __DIR__)

  test "page_bytes.js decodes elm-pages route bytes from HTML" do
    case System.find_executable("node") do
      nil ->
        :ok

      node ->
        {output, code} = System.cmd(node, [@self_test], stderr_to_stdout: true)
        assert code == 0, output
        assert output =~ "rc_ok"
    end
  end
end
