# Captures an embedded-emulator screenshot for watchface-smoke-screen and verifies
# four-quadrant checkerboard pixels. Run from ide/:
#
#   ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 mix run scripts/capture_smoke_checkerboard_screenshot.exs
#
# Writes PNG to /tmp/smoke-checkerboard-<platform>.png and prints quadrant analysis.

defmodule SmokeScreenshotVerify do
  def decode_png_rgb(png) when is_binary(png) do
    tmp_in = Path.join(System.tmp_dir!(), "smoke-decode-in-#{:rand.uniform(999_999)}.png")
    tmp_out = Path.join(System.tmp_dir!(), "smoke-decode-out-#{:rand.uniform(999_999)}.raw")

    try do
      File.write!(tmp_in, png)

      case System.cmd("magick", [tmp_in, "-depth", "8", "rgb:", tmp_out], stderr_to_stdout: true) do
        {_, 0} ->
          raw = File.read!(tmp_out)
          {dim_out, 0} = System.cmd("magick", ["identify", "-format", "%w %h", tmp_in], stderr_to_stdout: true)
          [sw, sh] = String.split(String.trim(dim_out))
          w = String.to_integer(sw)
          h = String.to_integer(sh)
          expected = w * h * 3

          if byte_size(raw) != expected do
            {:error, "raw rgb size #{byte_size(raw)} != #{expected} for #{w}x#{h}"}
          else
            {:ok, {w, h, raw}}
          end

        {msg, _} ->
          {:error, "ImageMagick failed: #{String.trim(msg)}"}
      end
    after
      File.rm(tmp_in)
      File.rm(tmp_out)
    end
  end

  def verify_quadrants(w, h, rgb) when w > 0 and h > 0 do
    samples =
      for {qx, qy, expect} <- [
            {0.25, 0.25, :dark},
            {0.75, 0.25, :light},
            {0.25, 0.75, :light},
            {0.75, 0.75, :dark}
          ] do
        x = min(trunc(w * qx), w - 1)
        y = min(trunc(h * qy), h - 1)
        offset = (y * w + x) * 3
        <<r, g, b>> = binary_part(rgb, offset, 3)
        lum = div(r * 30 + g * 59 + b * 11, 100)
        got = if lum < 128, do: :dark, else: :light
        {qx, qy, x, y, r, g, b, lum, expect, got}
      end

    Enum.each(samples, fn {qx, qy, x, y, r, g, b, lum, expect, got} ->
      IO.puts(
        "  quadrant (#{qx},#{qy}) pixel (#{x},#{y}) rgb=#{r},#{g},#{b} lum=#{lum} expect=#{expect} got=#{got}"
      )
    end)

    case Enum.find(samples, fn {_, _, _, _, _, _, _, _, expect, got} -> expect != got end) do
      nil ->
        :ok

      {qx, qy, _, _, r, g, b, lum, expect, got} ->
        {:error,
         "quadrant (#{qx},#{qy}) expected #{expect} but got #{got} (rgb #{r},#{g},#{b} lum=#{lum})"}
    end
  end

  def analyze_checkerboard_png(png) when is_binary(png) do
    with {:ok, {w, h, rgb}} <- decode_png_rgb(png),
         :ok <- verify_quadrants(w, h, rgb) do
      :ok
    end
  end
end

unless System.get_env("ELMC_RUN_EMBEDDED_EMULATOR_LIVE") in ["1", "true", "TRUE", "yes", "YES"] do
  IO.puts("Set ELMC_RUN_EMBEDDED_EMULATOR_LIVE=1 to run this script.")
  System.halt(0)
end

Code.require_file("test/support/emulator_session_env.ex")

alias Ide.Emulator
alias Ide.Emulator.Workflow
alias Ide.Projects
alias Ide.TestSupport.EmulatorSessionEnv

platform = System.get_env("ELMC_SMOKE_PLATFORM", "diorite")
png_path = Path.join(System.tmp_dir!(), "smoke-checkerboard-#{platform}.png")

EmulatorSessionEnv.run_live(fn ->
  root =
    Path.join(
      System.tmp_dir!(),
      "smoke-screenshot-#{System.unique_integer([:positive])}"
    )

  Application.put_env(:ide, Ide.Projects, projects_root: root)

  {:ok, project} =
    Projects.create_project(%{
      "name" => "Smoke Screenshot",
      "slug" => "smoke-shot-#{System.unique_integer([:positive])}",
      "target_type" => "watchface",
      "template" => "watchface-smoke-screen"
    })

  {:ok, launched} = Workflow.launch_project(project, platform)
  session_id = launched.session.id

  try do
    :ok = Workflow.wait_display_ready(session_id, timeout_ms: 120_000)
    Process.sleep(2_000)

    {:ok, install} = Emulator.install(session_id)
    IO.puts("installed uuid=#{install.uuid}")

    Process.sleep(5_000)

    {:ok, png} = Emulator.screenshot(session_id, [])
    File.write!(png_path, png)
    IO.puts("wrote #{png_path} (#{byte_size(png)} bytes)")

    case SmokeScreenshotVerify.analyze_checkerboard_png(png) do
      :ok ->
        IO.puts("CHECKERBOARD OK: four quadrants match expected black/white pattern")
        System.halt(0)

      {:error, reason} ->
        IO.puts("CHECKERBOARD FAIL: #{reason}")
        IO.puts("Open #{png_path} to inspect visually.")
        System.halt(1)
    end
  after
    _ = Emulator.kill(session_id)
  end
end)
