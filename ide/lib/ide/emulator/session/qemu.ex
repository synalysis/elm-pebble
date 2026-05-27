defmodule Ide.Emulator.Session.Qemu do
  @moduledoc false

  alias Ide.Emulator.SdkImages
  alias Ide.Emulator.Session.{Bins, Config}
  alias Ide.Emulator.Types
  alias Ide.WatchModels

  @type features :: %{required(:new_qemu?) => boolean(), required(:machines) => MapSet.t()}

  @type state_slice :: Types.qemu_args_state()

  @spec features() :: Types.qemu_features()
  def features do
    case Bins.qemu_bin() do
      {:ok, qemu_bin} ->
        %{
          new_qemu?: qemu_major_version(qemu_bin) >= 7,
          machines: qemu_machines(qemu_bin)
        }

      {:error, _reason} ->
        %{new_qemu?: false, machines: MapSet.new()}
    end
  end

  @spec args(state_slice() | Types.session_state()) :: [String.t()]
  def args(state) do
    image_dir = image_dir(state.platform)
    micro_flash = Path.join(image_dir, "qemu_micro_flash.bin")
    qemu_features = Map.get(state, :qemu_features) || features()
    tcp_opts = "server=on,wait=off"

    firmware_args =
      if qemu_features.new_qemu?, do: ["-kernel", micro_flash], else: ["-pflash", micro_flash]

    pc_bios_args =
      if qemu_features.new_qemu?,
        do: keymap_args(state),
        else: ["-L", pc_bios_dir()]

    base =
      [
        "-rtc",
        "base=localtime",
        "-serial",
        "null",
        "-serial",
        "tcp:127.0.0.1:#{state.bt_port},#{tcp_opts}",
        "-serial",
        "tcp:127.0.0.1:#{state.console_port},#{tcp_opts}"
      ] ++
        firmware_args ++
        [
          "-monitor",
          "stdio"
        ] ++
        pc_bios_args ++
        [
          "-vnc",
          ":#{state.vnc_display}"
        ]

    base ++ machine_args(state.platform, state.spi_image_path, qemu_features)
  end

  @spec machine_args(String.t(), String.t() | nil, features()) :: [String.t()]
  def machine_args(platform, spi_image_path, qemu_features \\ %{new_qemu?: false, machines: MapSet.new()}) do
    spi_pflash =
      if qemu_features.new_qemu? do
        ["-drive", "if=none,id=spi-flash,file=#{spi_image_path},format=raw"]
      else
        ["-pflash", spi_image_path]
      end

    new_mtd_flash = ["-drive", "if=mtd,format=raw,file=#{spi_image_path}"]

    new_board? =
      qemu_features.new_qemu? and MapSet.member?(qemu_features.machines, "pebble-emery")

    audio_none = if new_board?, do: ["-audio", "driver=none,id=audio0"], else: []

    case platform do
      "aplite" ->
        ["-machine", "pebble-bb2", "-mtdblock", spi_image_path, "-cpu", "cortex-m3"]

      "basalt" ->
        ["-machine", "pebble-snowy-bb", "-cpu", "cortex-m4"] ++ spi_pflash

      "chalk" ->
        ["-machine", "pebble-s4-bb", "-cpu", "cortex-m4"] ++ spi_pflash

      "diorite" ->
        ["-machine", "pebble-silk-bb", "-mtdblock", spi_image_path, "-cpu", "cortex-m4"]

      "emery" ->
        if new_board? do
          ["-machine", "pebble-emery", "-cpu", "cortex-m33"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] ++ spi_pflash
        end

      "flint" ->
        if new_board? do
          ["-machine", "pebble-flint", "-cpu", "cortex-m4"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-silk-bb", "-cpu", "cortex-m4", "-mtdblock", spi_image_path]
        end

      "gabbro" ->
        if new_board? do
          ["-machine", "pebble-gabbro", "-cpu", "cortex-m33"] ++ new_mtd_flash ++ audio_none
        else
          ["-machine", "pebble-snowy-emery-bb", "-cpu", "cortex-m4"] ++ spi_pflash
        end

      _ ->
        machine_args(WatchModels.default_id(), spi_image_path, qemu_features)
    end
  end

  @spec boot_markers() :: [String.t()]
  def boot_markers, do: ["Ready for communication"]

  @spec firmware_failure?(binary()) :: boolean()
  def firmware_failure?(data) do
    Enum.any?(["Invalid firmware description", "SAD WATCH"], fn marker ->
      :binary.match(data, marker) != :nomatch
    end)
  end

  @spec console_tail(binary()) :: String.t()
  def console_tail(data) when is_binary(data) do
    size = byte_size(data)
    tail_size = min(size, 256)
    tail = binary_part(data, size - tail_size, tail_size)

    if String.valid?(tail) do
      tail
    else
      "base16:" <> Base.encode16(tail, case: :lower)
    end
  end

  @spec emulator_state_dir(String.t(), String.t()) :: String.t()
  def emulator_state_dir(session_key, platform) do
    root = Config.config(:state_root, Path.join(System.tmp_dir!(), "elm-pebble-emulator-state"))

    Path.join([
      root,
      safe_path_fragment(session_key, "project"),
      safe_path_fragment(platform, "platform")
    ])
  end

  @spec make_persist_dir(String.t(), String.t()) :: {:ok, String.t()} | {:error, Types.session_tuple_error()}
  def make_persist_dir(platform, project_slug) do
    dir = Path.join(emulator_state_dir(project_slug, platform), "pypkjs")

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, {:persist_dir_failed, reason}}
    end
  end

  @spec make_spi_image(String.t(), String.t()) :: {:ok, String.t()} | {:error, Types.session_error()}
  def make_spi_image(platform, project_slug) do
    source_dir = image_dir(platform)
    raw = Path.join(source_dir, "qemu_spi_flash.bin")
    bz2 = raw <> ".bz2"
    path = Path.join(emulator_state_dir(project_slug, platform), "qemu_spi_flash.bin")

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      cond do
        File.exists?(raw) ->
          File.cp(raw, path)
          {:ok, path}

        File.exists?(bz2) ->
          decompress_bzip2(bz2, path)

        Config.start_processes?() ->
          {:error, {:qemu_flash_image_not_found, source_dir}}

        true ->
          File.touch(path)
          {:ok, path}
      end
    end
  end

  @spec reset_spi_image(String.t(), String.t()) :: {:ok, String.t()} | {:error, Types.session_error()}
  def reset_spi_image(platform, path) do
    source_dir = image_dir(platform)
    raw = Path.join(source_dir, "qemu_spi_flash.bin")
    bz2 = raw <> ".bz2"

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      cond do
        File.exists?(raw) -> with :ok <- File.cp(raw, path), do: {:ok, path}
        File.exists?(bz2) -> decompress_bzip2(bz2, path)
        true -> {:error, {:qemu_flash_image_not_found, source_dir}}
      end
    end
  end

  @spec image_dir(String.t()) :: String.t()
  def image_dir(platform) do
    image_roots()
    |> Enum.find(fn root -> SdkImages.images_present?(root, platform) end)
    |> case do
      root when is_binary(root) -> Path.join([root, platform, "qemu"])
      nil -> Path.join([preferred_image_root(), platform, "qemu"])
    end
  end

  @spec micro_flash_present?(String.t()) :: boolean()
  def micro_flash_present?(platform),
    do: File.exists?(Path.join(image_dir(platform), "qemu_micro_flash.bin"))

  @spec spi_flash_available?(String.t()) :: boolean()
  def spi_flash_available?(platform) do
    raw = Path.join(image_dir(platform), "qemu_spi_flash.bin")
    File.exists?(raw) or File.exists?(raw <> ".bz2")
  end

  @spec image_roots() :: [String.t()]
  def image_roots do
    configured_root = Config.config(:qemu_image_root, nil)

    configured_roots =
      if is_binary(configured_root) and configured_root != "", do: [configured_root], else: []

    sdk_roots = Enum.map(Bins.sdk_roots(), &Path.join(&1, "sdk-core/pebble"))

    (Bins.qemu_bin_image_roots() ++ configured_roots ++ sdk_roots)
    |> Enum.uniq()
  end

  @spec preferred_image_root() :: String.t()
  def preferred_image_root do
    case Config.config(:qemu_image_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        image_roots()
        |> List.first()
        |> case do
          root when is_binary(root) -> root
          nil -> ""
        end
    end
  end

  @spec health(String.t()) :: :ok | {:error, String.t()}
  def health(path) do
    case System.cmd(path, ["--version"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        {:error, health_detail(path, output, exit_code)}
    end
  rescue
    error -> {:error, "not runnable: #{Exception.message(error)}"}
  end

  defp decompress_bzip2(source, target) do
    case System.find_executable("bzip2") || System.find_executable("bunzip2") do
      nil ->
        {:error, :bzip2_not_found}

      bin ->
        {data, exit_code} = System.cmd(bin, ["-dc", source], stderr_to_stdout: true)

        if exit_code == 0 do
          File.write(target, data)
          {:ok, target}
        else
          {:error, {:bzip2_failed, data}}
        end
    end
  end

  defp safe_path_fragment(value, fallback) do
    value
    |> to_string()
    |> String.trim()
    |> then(fn
      "" -> fallback
      text -> text
    end)
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
  end

  defp keymap_args(state) do
    root = Path.join(Map.get(state, :persist_dir) || System.tmp_dir!(), "qemu-pc-bios")
    keymap_dir = Path.join(root, "keymaps")
    target = Path.join(keymap_dir, "en-us")

    with :ok <- File.mkdir_p(keymap_dir),
         {:ok, content} <- keymap_content(),
         :ok <- File.write(target, content) do
      ["-L", root]
    else
      _ -> []
    end
  end

  defp keymap_content do
    source = Path.join(pc_bios_dir(), "keymaps/en-us")

    case File.read(source) do
      {:ok, content} ->
        content =
          content
          |> String.split("\n")
          |> Enum.reject(&(String.trim(&1) |> String.starts_with?("include ")))
          |> Enum.join("\n")

        {:ok, content}

      {:error, _reason} ->
        {:ok, "map 0x409\n"}
    end
  end

  defp pc_bios_dir do
    Enum.find_value(data_roots(), fn root ->
      if File.exists?(Path.join(root, "keymaps/en-us")), do: root
    end) || ""
  end

  defp data_roots do
    configured_root = Config.config(:qemu_data_root, nil)

    configured_roots =
      if is_binary(configured_root) and configured_root != "", do: [configured_root], else: []

    sdk_roots =
      Enum.map(Bins.sdk_roots(), fn root ->
        Path.join(root, "toolchain/lib/pc-bios")
      end)

    qemu_sdk_roots =
      case Bins.qemu_bin() do
        {:ok, path} ->
          case Bins.qemu_bin_sdk_root(path) do
            root when is_binary(root) -> [Path.join(root, "toolchain/lib/pc-bios")]
            nil -> []
          end

        {:error, _reason} ->
          []
      end

    system_roots = ["/usr/share/qemu", "/usr/local/share/qemu"]

    configured_roots ++ qemu_sdk_roots ++ sdk_roots ++ system_roots
  end

  defp qemu_major_version(qemu_bin) do
    case System.cmd(qemu_bin, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/version\s+(\d+)\./, output) do
          [_, major] -> String.to_integer(major)
          _ -> 0
        end

      {_output, _exit_code} ->
        0
    end
  rescue
    _ -> 0
  end

  defp qemu_machines(qemu_bin) do
    case System.cmd(qemu_bin, ["-machine", "help"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.map(fn line ->
          line |> String.trim() |> String.split(~r/\s+/, parts: 2) |> List.first()
        end)
        |> Enum.reject(&(&1 in [nil, "", "Supported"]))
        |> MapSet.new()

      {_output, _exit_code} ->
        MapSet.new()
    end
  rescue
    _ -> MapSet.new()
  end

  defp health_detail(path, output, exit_code) do
    output = String.trim(output || "")

    cond do
      String.contains?(output, "libpixman-1.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew pixman at /usr/local/opt/pixman. " <>
          "Install Rosetta and x86_64 Homebrew pixman with: arch -x86_64 /usr/local/bin/brew install pixman"

      String.contains?(output, "libSDL2-2.0.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew sdl2 at /usr/local/opt/sdl2. " <>
          "Install Rosetta and x86_64 Homebrew sdl2 with: arch -x86_64 /usr/local/bin/brew install sdl2"

      String.contains?(output, "libgthread-2.0.0.dylib") ->
        "#{path} is not runnable: missing x86_64 Homebrew glib at /usr/local/opt/glib. " <>
          "Install Rosetta and x86_64 Homebrew glib with: arch -x86_64 /usr/local/bin/brew install glib"

      String.contains?(output, "Library not loaded") ->
        "#{path} is not runnable: #{single_line(output)}"

      library = missing_linux_shared_library(output) ->
        linux_shared_library_detail(path, library)

      output != "" ->
        "#{path} exited with #{exit_code}: #{single_line(output)}"

      true ->
        "#{path} exited with #{exit_code}"
    end
  end

  defp single_line(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.join(" ")
  end

  defp missing_linux_shared_library(output) do
    case Regex.run(~r/error while loading shared libraries: ([^:]+):/, output) do
      [_match, library] -> library
      _ -> nil
    end
  end

  defp linux_shared_library_detail(path, "libsndio.so.7") do
    "#{path} is not runnable: missing Linux shared library libsndio.so.7. " <>
      "Debian/Ubuntu: install libsndio7.0. " <>
      "Fedora: sndio is not currently in the standard Fedora repositories; install a compatible sndio package from a trusted source or build sndio from source, then recheck."
  end

  defp linux_shared_library_detail(path, "libpixman-1.so.0") do
    "#{path} is not runnable: missing Linux shared library libpixman-1.so.0. " <>
      "Debian/Ubuntu: install libpixman-1-0 (Docker: rebuild the IDE image with qemu-system-common). " <>
      "Fedora: install pixman, then recheck."
  end

  defp linux_shared_library_detail(path, "libSDL2-2.0.so.0") do
    "#{path} is not runnable: missing Linux shared library libSDL2-2.0.so.0. " <>
      "Debian/Ubuntu: install libsdl2-2.0-0, then recheck."
  end

  defp linux_shared_library_detail(path, library) do
    "#{path} is not runnable: missing Linux shared library #{library}. " <>
      "Install the OS package that provides #{library}, then recheck."
  end
end
