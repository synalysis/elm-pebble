defmodule Ide.Handheld.MscMountTest do
  use ExUnit.Case, async: true

  alias Ide.Handheld.MscMount

  test "uses the MeowKit volume and ignores another USB stick" do
    blocks = [
      disk("sdb", "Generic", "Flash", [
        part("STICK", "vfat", "/run/media/stick")
      ]),
      disk("sdc", "Espressif", "USB_MSC", [
        part("MEOWKIT", "vfat", "/run/media/meow")
      ])
    ]

    assert MscMount.find(blocks: blocks) == {:ok, "/run/media/meow"}
  end

  test "reports when the card is not shared over USB" do
    blocks = [
      disk("sda", "Flipper", "Aizar", [
        part("", "", "")
      ])
    ]

    assert MscMount.find(blocks: blocks) == {:error, :not_mounted}
    assert MscMount.message(:not_mounted) =~ "USB Mass Storage"
    assert MscMount.message(:not_mounted) =~ "Leave the card"
  end

  test "asks which drive when two MeowKit volumes are mounted" do
    blocks = [
      disk("sdb", "Espressif", "USB_MSC", [part("", "vfat", "/run/media/one")]),
      disk("sdc", "TinyUSB", "Mass Storage", [part("", "exfat", "/run/media/two")])
    ]

    assert MscMount.find(blocks: blocks) == {:error, :ambiguous}
  end

  defp disk(name, vendor, model, children) do
    %{
      "name" => name,
      "tran" => "usb",
      "rm" => true,
      "vendor" => vendor,
      "model" => model,
      "children" => children
    }
  end

  defp part(label, fstype, mount) do
    %{
      "label" => label,
      "fstype" => fstype,
      "mountpoint" => mount,
      "mountpoints" => if(mount == "", do: [], else: [mount])
    }
  end
end
