defmodule Elmc.WasmWebFileTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @download_runner Path.expand("support/wasm_file_download_probe_runner.mjs", __DIR__)
  @select_runner Path.expand("support/wasm_file_select_probe_runner.mjs", __DIR__)
  @read_runner Path.expand("support/wasm_file_read_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm File.Download.string and bytes click <a download> with the payload" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_file_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_file_project", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "file_download"
        refute wat =~ "unimplemented"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@download_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "file_download_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm File.Download probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm File.Select delivers files and Download.url clicks <a href>" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_file_select_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_file/select", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "file_select"
        assert wat =~ "file_download_url"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@select_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "file_select_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm File.Select probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm File.toString, toUrl, and toBytes read a selected File" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_file_read_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_file/read", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "file_to_string"
        assert wat =~ "file_to_url"
        assert wat =~ "file_to_bytes"
        assert wat =~ "file_select"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@read_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "file_read_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm File.toString/toUrl/toBytes probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm File.decoder accepts File and FileList values" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_file_decoder_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_file/decoder", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "file_decoder"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        node = System.find_executable("node")
        assert node

        {output, code} =
          System.cmd(
            node,
            [Path.expand("support/wasm_file_decoder_probe_runner.mjs", __DIR__), out_dir],
            stderr_to_stdout: true
          )

        if code == 0 do
          assert output =~ "rc_ok"
          assert output =~ "file_decoder_ok"
        else
          if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
            :ok
          else
            flunk("wasm file decoder probe failed:\n#{output}")
          end
        end
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
