defmodule Ide.Emulator.ProtocolMatrixLiveTest do
  @moduledoc """
  Live embedded-emulator walk of every `companion-demo-protocol-matrix` page.

  After install + boot Ping/Pong, presses Down + Select for Enum → Union →
  Record → List → Extras and asserts the real AppMessage wire tags (watch→phone
  and phone→watch). Host TEA injects `FromPhone` and cannot cover this path.

  Run with:

      ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 \\
        ./scripts/mix-test-limited.sh ide test/ide/emulator/protocol_matrix_live_test.exs --include live_emulator

  Requires Pebble QEMU images and toolchain (see `Ide.Emulator.runtime_status/1`).
  """
  use Ide.DataCase, async: false

  @moduletag :live_emulator

  alias Ide.Emulator
  alias Ide.Emulator.LogCapture
  alias Ide.Emulator.QemuControl
  alias Ide.Emulator.Workflow
  alias Ide.Projects
  alias Ide.TestSupport.EmulatorSessionEnv

  # Pebble QEMU button bitmasks (same as MCP open_from_launcher Select).
  @button_protocol 8
  @button_select_mask 4
  @button_down_mask 8

  # Wire tags from Companion.Internal (WatchToPhone 2..7, PhoneToWatch 201..209).
  @pages [
    %{
      name: "Enum",
      watch_tag: 3,
      phone_tags: [202],
      summary: "2/6"
    },
    %{
      name: "Union",
      watch_tag: 4,
      phone_tags: [203],
      summary: "3/6"
    },
    %{
      name: "Record",
      watch_tag: 5,
      phone_tags: [204],
      summary: "4/6"
    },
    %{
      name: "List",
      watch_tag: 6,
      phone_tags: [205],
      summary: "5/6"
    },
    %{
      name: "Extras",
      watch_tag: 7,
      phone_tags: [206, 207, 208, 209],
      summary: "6/6",
      settle_ms: 8_000
    }
  ]

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_emulator_protocol_matrix_live_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  @tag timeout: 480_000
  test "protocol matrix walks Ping→Extras with wire echoes on basalt" do
    if run_live?() do
      EmulatorSessionEnv.run_live(fn ->
        slug = "emulator-protocol-matrix-#{System.unique_integer([:positive])}"

        assert {:ok, project} =
                 Projects.create_project(%{
                   "name" => "Emulator Protocol Matrix",
                   "slug" => slug,
                   "target_type" => "app",
                   "template" => "companion-demo-protocol-matrix"
                 })

        on_exit(fn -> Projects.delete_project(project) end)

        assert {:ok, launched} = Workflow.launch_project(project, "basalt")
        session_id = launched.session.id

        try do
          assert :ok = Workflow.wait_display_ready(session_id, timeout_ms: 120_000)
          Process.sleep(2_000)

          {:ok, ctx} = Emulator.log_capture_context(session_id)

          # Cover install, boot Ping/Pong, and five Down+Select pages.
          log_task =
            Task.async(fn ->
              LogCapture.snapshot(ctx, duration_ms: 120_000)
            end)

          assert {:ok, install_result} = Emulator.install(session_id)
          assert is_binary(install_result.uuid)

          # Companion refresh + boot Ping/Pong (case 0 without Select).
          Process.sleep(8_000)

          Enum.each(@pages, fn page ->
            click_button(session_id, @button_down_mask)
            Process.sleep(400)
            click_button(session_id, @button_select_mask)
            Process.sleep(Map.get(page, :settle_ms, 5_000))
          end)

          :ok = Emulator.request_app_logs(session_id)
          Process.sleep(2_000)

          snapshot = Task.await(log_task, 130_000)
          joined = Enum.join(snapshot.lines ++ [snapshot.output], "\n")

          IO.puts("\n--- protocol matrix full walk uuid=#{install_result.uuid} ---")
          IO.puts("--- fault_detected=#{snapshot.fault_detected} lines=#{length(snapshot.lines)} ---")
          Enum.take(snapshot.lines, 150) |> Enum.each(&IO.puts/1)
          IO.puts("--- end ---\n")

          refute snapshot.fault_detected,
                 "App fault during protocol matrix walk:\n#{joined}"

          assert {:ok, png} = Emulator.screenshot(session_id, [])

          shot =
            Path.join(
              System.tmp_dir!(),
              "protocol-matrix-full-#{System.unique_integer([:positive])}.png"
            )

          File.write!(shot, png)

          assert wire_tag_seen?(joined, 2),
                 """
                 expected boot watch→phone Ping (tag 2).

                 screenshot=#{shot}
                 logs:
                 #{joined}
                 """

          assert phone_tag_seen?(joined, 201),
                 """
                 expected boot phone→watch Pong (tag 201).

                 screenshot=#{shot}
                 logs:
                 #{joined}
                 """

          Enum.each(@pages, fn page ->
            assert wire_tag_seen?(joined, page.watch_tag),
                   """
                   expected watch→phone tag=#{page.watch_tag} after Select on #{page.name}.

                   Host TEA injects FromPhone; this live walk covers the real AppMessage path.

                   screenshot=#{shot}
                   logs:
                   #{joined}
                   """

            Enum.each(page.phone_tags, fn phone_tag ->
              assert phone_tag_seen?(joined, phone_tag),
                     """
                     expected phone→watch tag=#{phone_tag} for #{page.name} (summary #{page.summary}).

                     screenshot=#{shot}
                     logs:
                     #{joined}
                     """
            end)
          end)
        after
          _ = Emulator.kill(session_id)
        end
      end)
    else
      assert true
    end
  end

  defp wire_tag_seen?(text, tag) when is_binary(text) and is_integer(tag) do
    tag_s = Integer.to_string(tag)

    String.contains?(text, "watch -> companion tag=#{tag_s}") or
      Regex.match?(~r/tag=#{Regex.escape(tag_s)}(?:\D|$)/, text) or
      Regex.match?(~r/"10":#{Regex.escape(tag_s)}(?:\D|$)/, text)
  end

  defp phone_tag_seen?(text, tag) when is_binary(text) and is_integer(tag) do
    tag_s = Integer.to_string(tag)

    Regex.match?(~r/tag=#{Regex.escape(tag_s)}(?:\D|$)/, text) or
      Regex.match?(~r/"10":#{Regex.escape(tag_s)}(?:\D|$)/, text) or
      Regex.match?(~r/enqueue tag=#{Regex.escape(tag_s)}(?:\D|$)/, text) or
      Regex.match?(
        ~r/(?:phone→watch|phone->watch|Companion phone)[^\n]*tag[=:]#{Regex.escape(tag_s)}(?:\D|$)/,
        text
      )
  end

  defp click_button(session_id, mask) do
    %{protocol: protocol, payload: press} = QemuControl.encode_button(mask)
    %{payload: release} = QemuControl.encode_button(0)
    assert protocol == @button_protocol
    assert :ok = Emulator.control(session_id, protocol, press)
    Process.sleep(150)
    assert :ok = Emulator.control(session_id, protocol, release)
    :ok
  end

  defp run_live? do
    System.get_env("ELMC_RUN_EMBEDDED_EMULATOR_LIVE", "0") in ["1", "true", "TRUE", "yes", "YES"]
  end
end
