defmodule Ide.Handheld.MscMount do
  @moduledoc """
  Finds the MeowKit SD card when the device is in USB Mass Storage mode.

  The card stays in the MeowKit. Settings → USB Mass Storage presents it as a
  drive. This module does not pick an unrelated USB stick.
  """

  @filesystems ~w(vfat exfat msdos)

  @spec find(keyword()) :: {:ok, String.t()} | {:error, :not_mounted | :ambiguous | :mount_missing}
  def find(opts \\ []) do
    cond do
      Keyword.has_key?(opts, :mount) ->
        case explicit(opts[:mount]) do
          :skip -> from_blocks(opts)
          other -> other
        end

      Keyword.has_key?(opts, :blocks) ->
        from_blocks(opts)

      true ->
        case explicit(System.get_env("MEOW_MSC_MOUNT")) do
          :skip -> from_blocks(opts)
          other -> other
        end
    end
  end

  @spec message(:not_mounted | :ambiguous | :mount_missing) :: String.t()
  def message(:not_mounted) do
    "MeowKit is not sharing its card over USB. On the device, open Settings → USB Mass Storage, then install again. Leave the card in the MeowKit."
  end

  def message(:ambiguous) do
    "More than one USB drive looks like a MeowKit. Set MEOW_MSC_MOUNT to the right folder."
  end

  def message(:mount_missing) do
    "MEOW_MSC_MOUNT is set, but that folder is not there."
  end

  defp explicit(mount) when is_binary(mount) and mount != "" do
    if File.dir?(mount), do: {:ok, mount}, else: {:error, :mount_missing}
  end

  defp explicit(_), do: :skip

  defp from_blocks(opts) do
    blocks = Keyword.get(opts, :blocks, list_blocks())

    case ranked(blocks) do
      [] -> {:error, :not_mounted}
      [{_score, path}] -> {:ok, path}
      [{score, path}, {other, _} | _] when score > other -> {:ok, path}
      _ -> {:error, :ambiguous}
    end
  end

  defp ranked(blocks) when is_list(blocks) do
    blocks
    |> flatten(%{label: "", vendor: "", fstype: "", usb: false})
    |> Enum.map(fn node -> {score(node), node.mount} end)
    |> Enum.filter(fn {score, _mount} -> score > 0 end)
    |> Enum.sort_by(fn {score, mount} -> {-score, mount} end)
  end

  defp ranked(_), do: []

  defp flatten(nodes, inherited) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      info = inherit(inherited, node)

      mounts =
        mountpoints(node)
        |> Enum.map(fn path -> Map.put(info, :mount, path) end)

      mounts ++ flatten(children(node), info)
    end)
  end

  defp flatten(_, _), do: []

  defp inherit(parent, node) do
    parent
    |> put_text(:label, node["label"])
    |> put_text(:vendor, vendor_text(node))
    |> put_text(:fstype, node["fstype"])
    |> Map.update(:usb, false, fn usb ->
      usb or node["tran"] == "usb" or node["rm"] in [true, "1", 1]
    end)
  end

  defp put_text(map, _key, value) when value in [nil, ""], do: map

  defp put_text(map, :fstype, value) when is_binary(value) do
    Map.put(map, :fstype, String.downcase(String.trim(value)))
  end

  defp put_text(map, key, value) when is_binary(value) do
    Map.put(map, key, String.downcase(String.trim(value)))
  end

  defp put_text(map, _key, _value), do: map

  defp vendor_text(node) do
    [node["vendor"], node["model"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp children(%{"children" => children}) when is_list(children), do: children
  defp children(_), do: []

  defp mountpoints(node) do
    case node["mountpoints"] do
      list when is_list(list) ->
        Enum.filter(list, &(is_binary(&1) and &1 != ""))

      _ ->
        case node["mountpoint"] do
          path when is_binary(path) and path != "" -> [path]
          _ -> []
        end
    end
  end

  defp score(%{mount: mount, fstype: fstype, label: label, vendor: vendor, usb: usb}) do
    cond do
      fstype not in @filesystems ->
        0

      String.contains?(label, "meow") ->
        100

      meow_tree?(mount) ->
        90

      usb and meow_vendor?(vendor) ->
        80

      true ->
        0
    end
  end

  defp meow_vendor?(vendor) do
    String.contains?(vendor, "meow") or String.contains?(vendor, "espressif") or
      String.contains?(vendor, "tinyusb")
  end

  defp meow_tree?(mount) do
    File.dir?(Path.join(mount, "badusb")) or File.regular?(Path.join(mount, ".meowkit"))
  end

  defp list_blocks do
    case System.cmd("lsblk", ["-J", "-o", "NAME,LABEL,MOUNTPOINT,MOUNTPOINTS,TRAN,RM,FSTYPE,VENDOR,MODEL"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"blockdevices" => devices}} when is_list(devices) -> devices
          _ -> []
        end

      _ ->
        []
    end
  end
end
