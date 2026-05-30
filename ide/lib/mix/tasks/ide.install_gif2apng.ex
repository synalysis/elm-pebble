defmodule Mix.Tasks.Ide.InstallGif2apng do
  @moduledoc """
  Builds [gif2apng](http://gif2apng.sourceforge.net/) 1.9 into `priv/bin/gif2apng`.

  The IDE uses this for animated bitmap GIF upload. Docker images include a system
  `gif2apng`; for local dev run:

      mix ide.install_gif2apng

  Override the download with `GIF2APNG_SRC_URL` or `GIF2APNG_VERSION` (see
  `scripts/install_gif2apng.sh`). After install, `Ide.Resources.GifToApng` prefers
  `priv/bin/gif2apng`, then `GIF2APNG_BIN`, then `PATH`.
  """
  use Mix.Task

  @shortdoc "Build gif2apng into priv/bin for animated GIF resources"

  @impl Mix.Task
  def run(args) do
    root = File.cwd!()
    script = Path.join(root, "scripts/install_gif2apng.sh")
    bin = Path.join(root, "priv/bin/gif2apng")

    unless File.exists?(script) do
      Mix.raise("Run from the ide/ app root (missing #{script})")
    end

    if "--check" in args do
      check!(bin)
    else
      install!(root, script, bin)
    end
  end

  defp check!(bin) do
    if File.exists?(bin) and not File.dir?(bin) do
      Mix.shell().info("gif2apng present at #{bin}")
    else
      Mix.raise("""
      gif2apng is not installed. Run:

          mix ide.install_gif2apng
      """)
    end
  end

  defp install!(root, script, bin) do
    {output, status} = System.cmd("bash", [script], cd: root, stderr_to_stdout: true)

    if status == 0 do
      Mix.shell().info(String.trim_trailing(output))
      Mix.shell().info("Animated GIF upload will use #{bin}")
    else
      Mix.raise("""
      gif2apng install failed (exit #{status}).

      #{output}

      Ensure build tools are available (g++, make, curl, unzip, zlib headers).
      """)
    end
  end
end
