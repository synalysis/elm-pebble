defmodule Ide.Handheld.Pack do
  @moduledoc """
  Packs an Elm handheld app for MeowKit SD loading or a Flipper FAP scaffold.
  Both targets use the same host ABI. Only MeowKit gets a custom loader package.
  """

  @spec pack(:meowkit | :flipper, String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def pack(target, dest_root, opts)
      when target in [:meowkit, :flipper] and is_binary(dest_root) do
    id = Keyword.get(opts, :id, "elm.app")
    name = Keyword.get(opts, :name, id)
    profile = Keyword.get(opts, :profile)
    root = meowkit_root()

    if File.dir?(root) do
      case target do
        :meowkit -> pack_meowkit(root, dest_root, id, name, profile, opts)
        :flipper -> pack_flipper(root, dest_root, id, name, profile, opts)
      end
    else
      {:error, {:meowkit_root_missing, root}}
    end
  end

  @doc """
  Uploads a packed Flipper app and starts it on the connected Flipper Zero.

  `artifact_path` is either the ufbt app directory or the `.fap` inside it.
  """
  @spec launch_flipper(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def launch_flipper(artifact_path, opts \\ []) when is_binary(artifact_path) do
    app = flipper_app_dir(artifact_path)
    custom_runner? = Keyword.has_key?(opts, :runner)
    runner = Keyword.get(opts, :runner, &run_ufbt_launch/1)
    note = if custom_runner?, do: "", else: sdk_note()

    if File.regular?(Path.join(app, "application.fam")) do
      case runner.(app) do
        {:ok, log} -> {:ok, note <> log}
        {:error, {:ufbt, status, output}} -> {:error, {:ufbt, status, note <> output}}
        other -> other
      end
    else
      {:error, :flipper_app_missing}
    end
  end

  defp sdk_note do
    case Ide.Handheld.FlipperSdk.ensure() do
      {:ok, note} -> note <> "\n\n"
      _ -> ""
    end
  end

  @spec launch_error_message(term()) :: String.t()
  def launch_error_message(:ufbt_missing),
    do:
      "ufbt is not on PATH. Install the Flipper SDK, connect the Flipper over USB, and try again."

  def launch_error_message(:flipper_app_missing),
    do: "The Flipper package has no application.fam, so it cannot be installed."

  def launch_error_message({:ufbt, status, output}) when is_binary(output) do
    hint =
      cond do
        String.contains?(output, "has to be closed manually") ->
          "The Flipper is showing an app that has to be closed on the device. Press Back until the main desktop is visible, then install again.\n\n"

        String.contains?(output, "ApiTooNew") ->
          "The Flipper firmware is older than the API this FAP was built with. Install again so the SDK can match the firmware on the device.\n\n"

        true ->
          ""
      end

    hint <> "ufbt launch exited #{status}.\n#{output}"
  end

  def launch_error_message(reason), do: inspect(reason)

  @spec copy_to_msc(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def copy_to_msc(package_dir, mount) when is_binary(package_dir) do
    cond do
      mount in [nil, ""] ->
        {:error, :no_mount}

      not File.dir?(mount) ->
        {:error, :mount_missing}

      true ->
        dest = Path.join([mount, "apps", Path.basename(package_dir)])
        File.mkdir_p!(dest)

        package_dir
        |> File.ls!()
        |> Enum.each(fn name ->
          File.cp!(Path.join(package_dir, name), Path.join(dest, name))
        end)

        {:ok, dest}
    end
  end

  defp pack_meowkit(root, dest_root, id, name, profile, opts) do
    app = Path.join([dest_root, "apps", id])
    File.mkdir_p!(app)

    manifest = %{
      "id" => id,
      "name" => name,
      "version" => "1.0.0",
      "abi" => %{"host" => 1, "modules" => %{"core" => 1, "graphics" => 1, "input" => 1}},
      "requires" => ["core", "graphics", "input"],
      "optional" => ["nfc", "ir", "usb", "gpio", "radio", "sensors"],
      "entry" => "meow_app_start",
      "heap_kb" => 256
    }

    File.write!(Path.join(app, "manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n")

    linked =
      if stage_elm(root, app, Keyword.get(opts, :elmc_out)) == :ok do
        File.cp!(Path.join(root, "include/handheld_host.h"), Path.join(app, "handheld_host.h"))

        case link_host_so(app) do
          :ok ->
            case link_xtensa(root, app) do
              :ok -> :ok
              :missing -> :ok
              {:error, output} -> {:error, output}
            end

          other ->
            other
        end
      else
        File.write!(Path.join(app, "app.meow"), host_blob(0))
        :ok
      end

    case linked do
      :ok ->
        write_profile(app, profile)

        File.cp!(
          Path.join(root, "emulator/meow_host_mock.js"),
          Path.join(app, "meow_host_mock.js")
        )

        maybe_msc(app)
        {:ok, app}

      {:error, output} ->
        {:error, {:link, output}}
    end
  end

  defp link_host_so(app) do
    sources = [
      "elmc_generated.c",
      "elmc_worker.c",
      "elmc_runtime.c",
      "elmc_ports.c",
      "meow_app_entry.c",
      "elmc_handheld_shim.c"
    ]

    paths = Enum.map(sources, &Path.join(app, &1))

    if Enum.all?(paths, &File.regular?/1) do
      so = Path.join(app, "app.so")

      case System.cmd(
             "gcc",
             [
               "-shared",
               "-fPIC",
               "-std=c11",
               "-D_GNU_SOURCE",
               "-I",
               app,
               "-o",
               so
               | paths
             ] ++ ["-lm"],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          File.write!(Path.join(app, "app.meow"), host_blob(File.stat!(so).size))
          :ok

        {output, _status} ->
          {:error, output}
      end
    else
      File.write!(Path.join(app, "app.meow"), host_blob(0))
      :ok
    end
  end

  defp link_xtensa(root, app) do
    gcc = xtensa_gcc()
    script = Path.join(root, "xtensa/link_image.py")
    ld = Path.join(root, "xtensa/app.ld")
    support = Path.join(root, "xtensa/meow_support.c")

    if gcc && File.regular?(script) do
      case System.cmd("python3", [script, gcc, app, ld, support], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, _status} -> {:error, output}
      end
    else
      :missing
    end
  end

  defp xtensa_gcc do
    env = System.get_env("XTENSA_GCC")
    path = System.find_executable("xtensa-esp32s3-elf-gcc")

    home =
      Path.join(System.user_home!(), ".local/espressif/xtensa-esp-elf/bin/xtensa-esp32s3-elf-gcc")

    cond do
      is_binary(env) and env != "" and File.regular?(env) -> env
      is_binary(path) -> path
      File.regular?(home) -> home
      true -> nil
    end
  end

  defp pack_flipper(root, dest_root, id, name, profile, opts) do
    app = Path.join(dest_root, id)
    File.mkdir_p!(app)

    fam =
      root
      |> Path.join("flipper/application.fam")
      |> File.read!()
      |> String.replace("elm_handheld", id)
      |> String.replace("name=\"Elm App\"", "name=\"#{flipper_label(name, id)}\"")

    File.write!(Path.join(app, "application.fam"), fam)
    File.cp!(Path.join(root, "flipper/flipper_host.c"), Path.join(app, "flipper_host.c"))
    File.cp!(Path.join(root, "flipper/flipper_host.h"), Path.join(app, "flipper_host.h"))
    File.cp!(Path.join(root, "include/handheld_host.h"), Path.join(app, "handheld_host.h"))

    built =
      if stage_elm(root, app, Keyword.get(opts, :elmc_out)) == :ok do
        File.rm(Path.join(app, "smoke_app.c"))
        run_ufbt(app, id)
      else
        File.cp!(Path.join(root, "flipper/smoke_app.c"), Path.join(app, "smoke_app.c"))
        {:ok, app}
      end

    case built do
      {:ok, path} ->
        write_profile(app, profile)
        {:ok, path}

      {:error, output} ->
        {:error, {:ufbt, output}}
    end
  end

  defp flipper_label(name, id) do
    label = if is_binary(name) and String.trim(name) != "", do: String.trim(name), else: id

    label
    |> String.replace("\\", "")
    |> String.replace("\"", "")
    |> String.replace(~r/[\r\n]/, " ")
  end

  defp flipper_app_dir(path) do
    cond do
      File.dir?(path) and File.regular?(Path.join(path, "application.fam")) ->
        path

      File.regular?(path) ->
        path |> Path.dirname() |> Path.dirname()

      true ->
        path
    end
  end

  defp run_ufbt_launch(app) do
    case System.find_executable("ufbt") do
      nil ->
        {:error, :ufbt_missing}

      ufbt ->
        case System.cmd(ufbt, ["launch"],
               cd: app,
               stderr_to_stdout: true,
               env: [{"NO_COLOR", "1"}, {"TERM", "dumb"}]
             ) do
          {output, 0} -> {:ok, strip_ansi(output)}
          {output, status} -> {:error, {:ufbt, status, strip_ansi(output)}}
        end
    end
  end

  defp strip_ansi(text) when is_binary(text) do
    String.replace(text, ~r/\e\[[0-9;]*m/, "")
  end

  defp run_ufbt(app, id) do
    fap = Path.join(app, "dist/#{id}.fap")

    case System.find_executable("ufbt") do
      nil ->
        {:ok, app}

      ufbt ->
        case System.cmd(ufbt, [], cd: app, stderr_to_stdout: true) do
          {_output, 0} -> {:ok, fap}
          {output, _status} -> {:error, output}
        end
    end
  end

  defp stage_elm(root, app, elmc_out) do
    generated = elmc_out && Path.join(elmc_out, "c/elmc_generated.c")

    if is_binary(generated) and File.regular?(generated) do
      File.cp!(Path.join(root, "meow_app_entry.c"), Path.join(app, "meow_app_entry.c"))

      File.cp!(
        Path.join(root, "shim/elmc_handheld_shim.c"),
        Path.join(app, "elmc_handheld_shim.c")
      )

      Enum.each(
        ["elmc_generated.c", "elmc_generated.h", "elmc_worker.c", "elmc_worker.h"],
        fn name ->
          src = Path.join(elmc_out, "c/#{name}")
          if File.regular?(src), do: File.cp!(src, Path.join(app, name))
        end
      )

      copy_dir(Path.join(elmc_out, "runtime"), app)
      copy_dir(Path.join(elmc_out, "ports"), app)
      flatten_includes(app)
      relax_flipper_warnings(app)
      :ok
    else
      :missing
    end
  end

  defp relax_flipper_warnings(dir) do
    dir
    |> File.ls!()
    |> Enum.each(fn name ->
      path = Path.join(dir, name)

      if File.regular?(path) and String.ends_with?(name, ".c") do
        File.write!(
          path,
          "#pragma GCC diagnostic ignored \"-Wredundant-decls\"\n" <> File.read!(path)
        )
      end
    end)
  end

  defp flatten_includes(dir) do
    dir
    |> File.ls!()
    |> Enum.each(fn name ->
      path = Path.join(dir, name)

      if File.regular?(path) and String.ends_with?(name, [".c", ".h"]) do
        updated =
          path
          |> File.read!()
          |> String.replace(
            "#include \"../runtime/elmc_runtime.h\"",
            "#include \"elmc_runtime.h\""
          )
          |> String.replace("#include \"../ports/elmc_ports.h\"", "#include \"elmc_ports.h\"")

        File.write!(path, updated)
      end
    end)
  end

  defp copy_dir(src, dest) do
    if File.dir?(src) do
      src
      |> File.ls!()
      |> Enum.each(fn name ->
        from = Path.join(src, name)
        if File.regular?(from), do: File.cp!(from, Path.join(dest, name))
      end)
    end
  end

  defp write_profile(_app, profile) when profile in [nil, ""], do: :ok

  defp write_profile(app, profile) when is_binary(profile) do
    File.write!(Path.join(app, "handheld.txt"), profile <> "\n")
  end

  defp maybe_msc(app) do
    case System.get_env("MEOW_MSC_MOUNT") do
      mount when is_binary(mount) and mount != "" -> copy_to_msc(app, mount)
      _ -> :ok
    end
  end

  defp host_blob(text_size) when is_integer(text_size) do
    # MEOW header, arch = host .so (2). Firmware relocates Xtensa blobs itself.
    <<
      "MEOW",
      1::little-16,
      2::little-16,
      text_size::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32
    >>
  end

  defp meowkit_root do
    Path.expand("../../../../elmc/priv/handheld", __DIR__)
  end
end
