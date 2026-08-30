defmodule Elmc.WasmWebHttpTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @tag :wasm_execute
  test "web wasm lowers Http.get to http runtime imports" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_project", __DIR__)
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
        assert wat =~ "http_command"
        assert wat =~ "http_expect"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )
    end
  end

  @tag :wasm_execute
  test "web wasm lowers Http.task and stringResolver to http task imports" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_task_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_task_project", __DIR__)
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
        assert wat =~ "http_task"
        assert wat =~ "http_string_resolver"
        assert wat =~ "http_empty_body"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_task_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_task_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http task probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.expectJson decodes the response body" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_json_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_json_project", __DIR__)
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
        assert wat =~ "http_command"
        assert wat =~ "http_expect_json"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_json_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_json_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http expectJson probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.expectBytes expectWhatever and multipartBody" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_multipart_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_multipart_project", __DIR__)
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
        assert wat =~ "http_expect_bytes"
        assert wat =~ "http_expect_whatever"
        assert wat =~ "http_multipart_body"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_multipart_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_multipart_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http multipart/expectBytes probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.expectStringResponse matches official Response and Metadata" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_string_response_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_string_response_project", __DIR__)
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
        assert wat =~ "http_expect_string_response"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_string_response_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_string_response_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http expectStringResponse probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.expectBytesResponse matches official Response Bytes" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_bytes_response_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_bytes_response_project", __DIR__)
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
        assert wat =~ "http_expect_bytes_response"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_bytes_response_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_bytes_response_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http expectBytesResponse probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.bytesResolver matches official Response Bytes on Http.task" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_bytes_resolver_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_bytes_resolver_project", __DIR__)
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
        assert wat =~ "http_bytes_resolver"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_bytes_resolver_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_bytes_resolver_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http bytesResolver probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.stringResolver cases on Response String and sends header/body" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_string_resolver_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_string_resolver_project", __DIR__)
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
        assert wat =~ "http_string_resolver"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_string_resolver_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_string_resolver_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http stringResolver probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.riskyTask fetches with credentials include" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_risky_task_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_risky_task_project", __DIR__)
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
        assert wat =~ "http_risky_task"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_risky_task_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_risky_task_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http riskyTask probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.riskyRequest sends jsonBody with credentials include" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_risky_request_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_risky_request_project", __DIR__)
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
        assert wat =~ "http_risky_command"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_risky_request_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_risky_request_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http riskyRequest/jsonBody probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.bytesBody posts official Bytes with the given MIME" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_bytes_body_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_bytes_body_project", __DIR__)
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
        assert wat =~ "http_command"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_bytes_body_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_bytes_body_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http bytesBody probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.request timeout Just ms delivers Http.Timeout" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_timeout_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_timeout_project", __DIR__)
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
        assert wat =~ "http_command"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_timeout_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_timeout_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http timeout probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Http.fileBody and filePart send the selected File" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_http_file_body_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_http_file_body_project", __DIR__)
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
        assert wat =~ "http_command"
        assert wat =~ "http_file_body" or wat =~ "http_pair"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_file_body_probe(out_dir) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "http_file_body_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("http fileBody/filePart probe failed:\n#{output}")
            end
        end
    end
  end

  @task_runner Path.expand("support/wasm_http_task_probe_runner.mjs", __DIR__)
  @json_runner Path.expand("support/wasm_http_json_probe_runner.mjs", __DIR__)
  @multipart_runner Path.expand("support/wasm_http_multipart_probe_runner.mjs", __DIR__)
  @string_response_runner Path.expand("support/wasm_http_string_response_probe_runner.mjs", __DIR__)
  @bytes_response_runner Path.expand("support/wasm_http_bytes_response_probe_runner.mjs", __DIR__)
  @bytes_resolver_runner Path.expand("support/wasm_http_bytes_resolver_probe_runner.mjs", __DIR__)
  @string_resolver_runner Path.expand("support/wasm_http_string_resolver_probe_runner.mjs", __DIR__)
  @risky_task_runner Path.expand("support/wasm_http_risky_task_probe_runner.mjs", __DIR__)
  @risky_request_runner Path.expand("support/wasm_http_risky_request_probe_runner.mjs", __DIR__)
  @bytes_body_runner Path.expand("support/wasm_http_bytes_body_probe_runner.mjs", __DIR__)
  @timeout_runner Path.expand("support/wasm_http_timeout_probe_runner.mjs", __DIR__)
  @file_body_runner Path.expand("support/wasm_http_file_body_probe_runner.mjs", __DIR__)

  defp run_task_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@task_runner, [out_dir])

  defp run_json_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@json_runner, [out_dir])

  defp run_multipart_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@multipart_runner, [out_dir])

  defp run_string_response_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@string_response_runner, [out_dir])

  defp run_bytes_response_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@bytes_response_runner, [out_dir])

  defp run_bytes_resolver_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@bytes_resolver_runner, [out_dir])

  defp run_string_resolver_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@string_resolver_runner, [out_dir])

  defp run_risky_task_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@risky_task_runner, [out_dir])

  defp run_risky_request_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@risky_request_runner, [out_dir])

  defp run_bytes_body_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@bytes_body_runner, [out_dir])

  defp run_timeout_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@timeout_runner, [out_dir])

  defp run_file_body_probe(out_dir),
    do: WasmRcTrackHarness.run_node_script(@file_body_runner, [out_dir])

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
