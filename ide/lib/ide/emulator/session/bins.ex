defmodule Ide.Emulator.Session.Bins do
  @moduledoc false

  alias Ide.Emulator.Session.Config

  @spec qemu_bin() :: {:ok, String.t()} | {:error, atom()}
  def qemu_bin do
    resolve_bin(
      Config.config(:qemu_bin, nil),
      ["qemu-pebble", "qemu-system-arm"],
      qemu_pebble_candidates(),
      :qemu_not_found
    )
  end

  @spec pypkjs_bin() :: {:ok, String.t()} | {:error, atom()}
  def pypkjs_bin do
    resolve_bin(
      Config.config(:pypkjs_bin, nil),
      ["pypkjs"],
      pypkjs_candidates(),
      :pypkjs_not_found
    )
  end

  @spec pebble_bin() :: {:ok, String.t()} | {:error, atom()}
  def pebble_bin do
    resolve_bin(
      Config.config(:pebble_bin, nil),
      ["pebble"],
      pebble_candidates(),
      :pebble_cli_not_found
    )
  end

  @spec sdk_roots() :: [String.t()]
  def sdk_roots do
    case Config.config(:sdk_roots, nil) do
      roots when is_list(roots) ->
        Enum.filter(roots, &is_binary/1)

      _ ->
        sdk_roots_for_os(System.user_home!())
    end
  end

  @spec preferred_sdk_root() :: String.t()
  def preferred_sdk_root do
    case Config.config(:sdk_install_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        sdk_roots()
        |> List.first()
        |> case do
          root when is_binary(root) -> root
          nil -> Path.expand(".pebble-sdk/SDKs/current", System.user_home!())
        end
    end
  end

  @spec sdk_version_root(String.t()) :: String.t()
  def sdk_version_root(version) do
    case Config.config(:sdk_install_root, nil) do
      root when is_binary(root) and root != "" ->
        root

      _ ->
        preferred_sdk_root()
        |> Path.dirname()
        |> Path.join(version)
    end
  end

  @spec qemu_bin_sdk_root(String.t()) :: String.t() | nil
  def qemu_bin_sdk_root(path) when is_binary(path) do
    marker = "/toolchain/bin/"

    case String.split(path, marker, parts: 2) do
      [root, _bin] when root != "" -> root
      _ -> nil
    end
  end

  @spec qemu_bin_image_roots() :: [String.t()]
  def qemu_bin_image_roots do
    case qemu_bin() do
      {:ok, path} ->
        path
        |> qemu_bin_sdk_root()
        |> case do
          nil -> []
          root -> [Path.join(root, "sdk-core/pebble")]
        end

      {:error, _reason} ->
        []
    end
  end

  @spec resolve_bin(String.t() | nil, [String.t()], [String.t()], atom()) ::
          {:ok, String.t()} | {:error, atom()}
  def resolve_bin(configured, fallbacks, candidates, error) do
    cond do
      executable_file?(configured) ->
        {:ok, configured}

      bin = find_executable(fallbacks) ->
        {:ok, bin}

      bin = Enum.find(candidates, &executable_file?/1) ->
        {:ok, bin}

      true ->
        {:error, error}
    end
  end

  @spec executable_file?(String.t() | nil) :: boolean()
  def executable_file?(path) when is_binary(path) and path != "" do
    File.exists?(path) and not File.dir?(path)
  end

  def executable_file?(_), do: false

  defp find_executable(fallbacks) do
    Enum.find_value(fallbacks, &System.find_executable/1)
  end

  defp qemu_pebble_candidates do
    sdk_roots()
    |> Enum.map(&Path.join(&1, "toolchain/bin/qemu-pebble"))
  end

  defp pypkjs_candidates do
    [
      Path.expand(".local/share/uv/tools/pebble-tool/bin/pypkjs", System.user_home!()),
      "/opt/pipx/venvs/pebble-tool/bin/pypkjs",
      "/usr/local/bin/pypkjs"
    ]
  end

  defp pebble_candidates do
    [
      Path.expand(".local/share/uv/tools/pebble-tool/bin/pebble", System.user_home!()),
      Path.expand(".local/bin/pebble", System.user_home!()),
      "/opt/pipx/venvs/pebble-tool/bin/pebble",
      "/usr/local/bin/pebble"
    ]
  end

  defp sdk_roots_for_os(home) do
    linux_roots = [
      Path.expand(".pebble-sdk/SDKs/current", home),
      Path.expand(".pebble-sdk/SDKs/4.9.169", home),
      Path.expand(".pebble-sdk/SDKs/4.9.148", home)
    ]

    mac_roots = [
      Path.expand("Library/Application Support/Pebble SDK/SDKs/current", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.169", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.148", home),
      Path.expand("Library/Application Support/Pebble SDK/SDKs/4.9.77", home)
    ]

    case :os.type() do
      {:unix, :darwin} -> mac_roots ++ linux_roots
      _ -> linux_roots ++ mac_roots
    end
  end
end
