defmodule Elmc.Backend.Handheld.Artifacts do
  @moduledoc """
  Copies the handheld host contract and the `meow_app_start` entry next to
  elmc C output. The MeowKit firmware does not live here. It loads the blob
  this target produces.
  """

  alias Elmc.Backend.Handheld

  @spec write(String.t(), map() | keyword()) :: :ok | {:error, term()}
  def write(out_dir, opts) when is_binary(out_dir) do
    root = root()
    dest = Path.join(out_dir, "handheld")
    targets = Handheld.targets(opts)
    packages = Handheld.packages(opts)

    with :ok <- mkdir(dest),
         :ok <- copy(root, dest, "include/handheld_host.h"),
         :ok <- copy(root, dest, "include/meow_host.h"),
         :ok <- copy(root, dest, "shim/elmc_handheld_shim.c"),
         :ok <- copy(root, dest, "meow_app_entry.c"),
         :ok <- copy(root, dest, "host/handheld_host_impl.h"),
         :ok <- copy(root, dest, "host/handheld_host_impl.c"),
         :ok <- maybe_flipper(root, dest, packages),
         :ok <- copy(root, dest, "emulator/meow_host_mock.js"),
         :ok <- File.write(Path.join(dest, "link.txt"), link_notes(targets)) do
      :ok
    end
  end

  @spec root() :: String.t()
  def root, do: Path.expand("../../../../priv/handheld", __DIR__)

  defp maybe_flipper(root, dest, packages) do
    if :flipper in packages do
      with :ok <- copy(root, dest, "flipper/application.fam"),
           :ok <- copy(root, dest, "flipper/flipper_host.c"),
           :ok <- copy(root, dest, "flipper/flipper_host.h"),
           :ok <- copy(root, dest, "flipper/smoke_app.c"),
           :ok <- copy(root, dest, "flipper/build_fap.sh") do
        :ok
      end
    else
      :ok
    end
  end

  defp mkdir(dest) do
    case File.mkdir_p(dest) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy(root, dest, rel) do
    case File.cp(Path.join(root, rel), Path.join(dest, Path.basename(rel))) do
      :ok -> :ok
      {:error, reason} -> {:error, {reason, rel}}
    end
  end

  defp link_notes(targets) do
    """
    targets: #{Enum.join(targets, ",")}
    Link meow_app_entry.c and elmc_handheld_shim.c with the generated worker.
    MeowKit firmware loads the resulting blob from the SD card.
    Flipper links the same objects into a FAP. flipper_app_main is the entry.
    """
  end
end
