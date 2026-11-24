defmodule Ide.Handheld.PackTest do
  use ExUnit.Case, async: true

  test "writes a meowkit sd package and a flipper fap scaffold" do
    dest = Path.join(System.tmp_dir!(), "ide-handheld-#{System.unique_integer([:positive])}")

    assert {:ok, app} =
             Ide.Handheld.Pack.pack(:meowkit, dest, id: "com.example.rain", name: "Rain")

    assert File.exists?(Path.join(app, "manifest.json"))
    assert File.exists?(Path.join(app, "app.meow"))
    assert File.exists?(Path.join(app, "meow_host_mock.js"))
    manifest = File.read!(Path.join(app, "manifest.json"))
    assert String.contains?(manifest, "meow_app_start")
    assert String.contains?(manifest, "\"nfc\"")

    assert {:error, :mount_missing} = Ide.Handheld.Pack.copy_to_msc(app, "/no/such/meow-mount")
    mount = Path.join(dest, "sd")
    File.mkdir_p!(mount)
    assert {:ok, copied} = Ide.Handheld.Pack.copy_to_msc(app, mount)
    assert File.exists?(Path.join(copied, "manifest.json"))

    assert {:ok, fap_dir} =
             Ide.Handheld.Pack.pack(:flipper, dest, id: "elm_handheld", name: "Elm")

    fap = Path.join(fap_dir, "dist/elm_handheld.fap")
    File.mkdir_p!(Path.dirname(fap))
    File.write!(fap, "fap")

    assert {:ok, "uploaded"} =
             Ide.Handheld.Pack.launch_flipper(fap,
               runner: fn dir ->
                 send(self(), {:launch_dir, dir})
                 {:ok, "uploaded"}
               end
             )

    assert_received {:launch_dir, ^fap_dir}

    assert {:error, :flipper_app_missing} =
             Ide.Handheld.Pack.launch_flipper(Path.join(dest, "missing.fap"))

    message =
      Ide.Handheld.Pack.launch_error_message(
        {:ufbt, 2, "Application \"Passport\" has to be closed manually"}
      )

    assert message =~ "Press Back until the main desktop is visible"

    {:ok, agent} = Agent.start_link(fn -> "88.2" end)

    assert {:ok, switched} =
             Ide.Handheld.FlipperSdk.ensure(
               firmware: fn -> {:ok, %{version: "1.4.3", api: "87.1"}} end,
               sdk_api: fn -> {:ok, Agent.get(agent, & &1)} end,
               updater: fn version ->
                 Agent.update(agent, fn _ -> "87.1" end)
                 send(self(), {:sdk, version})
                 :ok
               end
             )

    assert_received {:sdk, "1.4.3"}
    assert switched =~ "API 87.1"
    assert switched =~ "1.4.3 SDK"

    assert {:ok, matched} =
             Ide.Handheld.FlipperSdk.ensure(
               firmware: fn -> {:ok, %{version: "1.4.3", api: "87.1"}} end,
               sdk_api: fn -> {:ok, "87.1"} end,
               updater: fn _version -> flunk("sdk already matches") end
             )

    assert matched =~ "SDK matches"

    fam = File.read!(Path.join(fap_dir, "application.fam"))
    assert String.contains?(fam, "flipper_app_main")
    assert String.contains?(fam, "name=\"Elm\"")
    refute String.contains?(fam, "Elm App")
    assert File.exists?(Path.join(fap_dir, "flipper_host.c"))
    refute File.exists?(Path.join(fap_dir, "app.meow"))
  end
end
