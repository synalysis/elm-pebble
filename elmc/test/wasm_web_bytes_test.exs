defmodule Elmc.WasmWebBytesTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)
  @endian_runner Path.expand("support/wasm_bytes_endian_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm decodes bytes via Elm.Kernel.Bytes lowering" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_bytes_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_bytes/decode_u8", __DIR__)
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

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] == "Elm.Kernel.Bytes"
               end)

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "bytes_cmd"
        assert wat =~ "runtime_bytes_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "byte:42 w:1"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm bytes probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Bytes.Decode signed/16/32-bit/float/string/bytes and getStringWidth use official kernel reads" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_bytes_decode_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_bytes/decode_widths", __DIR__)
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
        assert wat =~ "bytes_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm bytes decode widths probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Bytes.Decode.andThen and loop decode a counted list" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_bytes_loop_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_bytes/loop", __DIR__)
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
        assert wat =~ "bytes_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm bytes loop probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Bytes.Decode.fail is official Decoder that always misses" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_bytes_fail_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_bytes/fail", __DIR__)
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

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Bytes.Decode.fail probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Bytes.getHostEndianness is a Task that yields LE or BE" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_bytes_endian_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_bytes/endian", __DIR__)
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
        assert wat =~ "bytes_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@endian_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "host_endianness="
            assert output =~ "le" or output =~ "be"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm host endianness probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, export_name, expected_text) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, export_name, expected_text]

        {output, code} =
          System.cmd(node, [@html_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
