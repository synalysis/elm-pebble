defmodule Elmc.Backend.CCodegen.LinkedBinaryReport do
  @moduledoc false

  @symbol_line_re ~r/^\s+0x[0-9a-fA-F]+\s+0x([0-9a-fA-F]+)\s+(.+)$/

  @spec from_app_build(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def from_app_build(app_root, opts \\ []) when is_binary(app_root) do
    build_dir = Path.join(app_root, "build")
    platform = Keyword.get(opts, :platform)

    with map_path when is_binary(map_path) <- find_map_file(build_dir, platform),
         {:ok, map_contents} <- File.read(map_path),
         elf_path <- find_elf_file(build_dir, platform, map_path) do
      {:ok, from_map(map_contents, elf_path: elf_path, map_path: map_path)}
    else
      nil -> {:error, :map_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec from_map(String.t(), keyword()) :: map()
  def from_map(contents, opts \\ []) when is_binary(contents) do
    symbols = parse_symbols(contents)
    elmc_symbols = Enum.filter(symbols, &elmc_symbol?/1)

    %{
      "available" => true,
      "map_path" => Keyword.get(opts, :map_path),
      "elf_path" => Keyword.get(opts, :elf_path),
      "elf_size" => elf_size(Keyword.get(opts, :elf_path)),
      "top_symbols" => Enum.take(symbols, 30) |> stringify_symbol_rows(),
      "elmc_symbols" => Enum.take(elmc_symbols, 40) |> stringify_symbol_rows(),
      "elmc_text_bytes" => Enum.reduce(elmc_symbols, 0, &(&1.size + &2))
    }
  end

  defp stringify_symbol_rows(rows) do
    Enum.map(rows, fn %{size: size, symbol: symbol} ->
      %{"size" => size, "symbol" => symbol}
    end)
  end

  @spec find_map_file(String.t(), String.t() | nil) :: String.t() | nil
  def find_map_file(build_dir, platform \\ nil) do
    candidates =
      case platform do
        platform when is_binary(platform) and platform != "" ->
          [Path.join([build_dir, platform, "pebble-app.map"])]

        _ ->
          [
            Path.join(build_dir, "basalt/pebble-app.map"),
            Path.join(build_dir, "flint/pebble-app.map"),
            Path.join(build_dir, "gabbro/pebble-app.map"),
            Path.join(build_dir, "diorite/pebble-app.map"),
            Path.join(build_dir, "aplite/pebble-app.map"),
            Path.join(build_dir, "chalk/pebble-app.map"),
            Path.join(build_dir, "pebble-app.map")
          ]
      end

    Enum.find_value(candidates, fn path ->
      if File.regular?(path), do: path
    end) ||
      (build_dir
       |> Path.join("**/pebble-app.map")
       |> Path.wildcard()
       |> Enum.sort()
       |> List.first())
  end

  defp find_elf_file(build_dir, platform, map_path) do
    candidates =
      case platform do
        platform when is_binary(platform) and platform != "" ->
          [Path.join([build_dir, platform, "pebble-app.elf"])]

        _ ->
          sibling = Path.join(Path.dirname(map_path), "pebble-app.elf")

          if File.regular?(sibling) do
            [sibling]
          else
            preferred_platform_elfs(build_dir)
          end
      end

    Enum.find_value(candidates, fn path ->
      if File.regular?(path), do: path
    end)
  end

  defp preferred_platform_elfs(build_dir) do
    ~w(basalt flint gabbro aplite diorite chalk emery)
    |> Enum.map(fn platform -> Path.join([build_dir, platform, "pebble-app.elf"]) end)
    |> Enum.filter(&File.regular?/1)
  end

  defp parse_symbols(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_symbol_line/1)
    |> Enum.sort_by(& &1.size, :desc)
  end

  defp parse_symbol_line(line) do
    case Regex.run(@symbol_line_re, line) do
      [_, size_hex, symbol] ->
        [%{size: parse_hex(size_hex), symbol: String.trim(symbol)}]

      _ ->
        []
    end
  end

  defp elmc_symbol?(%{symbol: symbol}) do
    String.contains?(symbol, "elmc_") or String.contains?(symbol, "Elmc")
  end

  defp elf_size(nil), do: nil

  defp elf_size(path) do
    with size_bin when is_binary(size_bin) <- find_arm_size(),
         {output, 0} <- System.cmd(size_bin, [path], stderr_to_stdout: true) do
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> parse_size_line()
    else
      _ -> file_bytes(path)
    end
  end

  defp find_arm_size do
    sdk_root = System.get_env("PEBBLE_SDK_ROOT")

    candidates =
      [
        System.find_executable("arm-none-eabi-size"),
        sdk_root && Path.join(sdk_root, "toolchain/arm-none-eabi/bin/arm-none-eabi-size"),
        Path.expand("~/.pebble-sdk/SDKs/4.9.169/toolchain/arm-none-eabi/bin/arm-none-eabi-size")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find(candidates, &File.regular?/1)
  end

  defp parse_size_line(nil), do: nil

  defp parse_size_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [text, data, bss, dec, hex | _] ->
        %{
          text: parse_int(text),
          data: parse_int(data),
          bss: parse_int(bss),
          dec: parse_int(dec),
          hex: hex
        }

      _ ->
        nil
    end
  end

  defp file_bytes(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} -> %{file_bytes: size}
      _ -> nil
    end
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_hex(value) do
    case Integer.parse(value, 16) do
      {int, _} -> int
      :error -> 0
    end
  end
end
