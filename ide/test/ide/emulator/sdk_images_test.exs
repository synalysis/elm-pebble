defmodule Ide.Emulator.SdkImagesTest do
  use ExUnit.Case, async: false

  alias Ide.Emulator.SdkImages

  test "images_present? requires micro flash and either raw or compressed spi flash" do
    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-images-test-#{System.unique_integer([:positive])}"
      )

    qemu_dir = Path.join([root, "basalt", "qemu"])
    File.mkdir_p!(qemu_dir)

    refute SdkImages.images_present?(root, "basalt")

    File.write!(Path.join(qemu_dir, "qemu_micro_flash.bin"), "")
    refute SdkImages.images_present?(root, "basalt")

    File.write!(Path.join(qemu_dir, "qemu_spi_flash.bin.bz2"), "")
    assert SdkImages.images_present?(root, "basalt")

    File.rm_rf!(root)
  end

  test "ensure_sdk_core extracts sdk-core archive" do
    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-core-test-#{System.unique_integer([:positive])}"
      )

    archive_path = write_sdk_core_archive!(root)
    sdk_root = Path.join(root, "SDKs/current")

    try do
      refute SdkImages.sdk_core_present?(sdk_root)
      assert :ok = SdkImages.ensure_sdk_core(sdk_root, archive_path: archive_path)
      assert SdkImages.sdk_core_present?(sdk_root)
    after
      File.rm_rf!(root)
    end
  end

  test "ensure_sdk_core creates SDK Python env when requirements exist" do
    previous_path = System.get_env("PATH")

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-python-env-test-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    uv_bin = Path.join(bin_dir, "uv")
    archive_path = write_sdk_core_archive!(root, include_requirements: true)
    sdk_root = Path.join(root, "SDKs/current")

    File.mkdir_p!(bin_dir)

    File.write!(uv_bin, """
    #!/bin/sh
    if [ "$1" = "venv" ]; then
      mkdir -p "$4/bin"
      touch "$4/bin/python"
      exit 0
    fi

    if [ "$1" = "pip" ]; then
      exit 0
    fi

    exit 1
    """)

    File.chmod!(uv_bin, 0o755)

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"
    System.put_env("PATH", path)

    try do
      assert :ok = SdkImages.ensure_sdk_core(sdk_root, archive_path: archive_path, python: "3.13")
      assert SdkImages.sdk_python_env_present?(sdk_root)
    after
      restore_env("PATH", previous_path)
      File.rm_rf!(root)
    end
  end

  test "ensure_sdk_core installs SDK node dependencies when package json exists" do
    previous_path = System.get_env("PATH")

    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-sdk-node-env-test-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    npm_bin = Path.join(bin_dir, "npm")
    archive_path = write_sdk_core_archive!(root, include_package_json: true)
    sdk_root = Path.join(root, "SDKs/current")

    File.mkdir_p!(bin_dir)

    File.write!(npm_bin, """
    #!/bin/sh
    mkdir -p node_modules
    exit 0
    """)

    File.chmod!(npm_bin, 0o755)

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"
    System.put_env("PATH", path)

    try do
      assert :ok = SdkImages.ensure_sdk_core(sdk_root, archive_path: archive_path)
      assert SdkImages.sdk_node_modules_present?(sdk_root)
      assert File.exists?(Path.join(sdk_root, "package.json"))
    after
      restore_env("PATH", previous_path)
      File.rm_rf!(root)
    end
  end

  test "ensure_toolchain extracts OS toolchain archive" do
    root =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-toolchain-test-#{System.unique_integer([:positive])}"
      )

    archive_path = write_toolchain_archive!(root)
    sdk_root = Path.join(root, "SDKs/current")

    try do
      refute SdkImages.toolchain_present?(sdk_root)

      assert :ok =
               SdkImages.ensure_toolchain(sdk_root,
                 toolchain_archive_path: archive_path,
                 os_name: "linux",
                 arch_name: "x86_64"
               )

      assert SdkImages.toolchain_present?(sdk_root)
    after
      File.rm_rf!(root)
    end
  end

  defp write_sdk_core_archive!(root, opts \\ []) do
    archive_path = Path.join(root, "sdk-core-test.tar.gz")
    source_root = Path.join(root, "sdk-core-archive")
    pebble_root = Path.join(source_root, "sdk-core/pebble")

    File.mkdir_p!(pebble_root)
    File.write!(Path.join(source_root, "sdk-core/manifest.json"), ~s({"version":"4.9.169"}))

    if Keyword.get(opts, :include_requirements, false) do
      File.write!(Path.join(source_root, "sdk-core/requirements.txt"), "pypng>=0.20220715.0\n")
    end

    if Keyword.get(opts, :include_package_json, false) do
      File.write!(Path.join(source_root, "sdk-core/package.json"), ~s({"dependencies":{}}))
    end

    {_, 0} = System.cmd("tar", ["czf", archive_path, "-C", source_root, "."])

    archive_path
  end

  defp write_toolchain_archive!(root) do
    archive_path = Path.join(root, "toolchain-test.tar.gz")
    source_root = Path.join(root, "toolchain-archive")
    qemu_bin = Path.join(source_root, "toolchain-linux-x86_64/bin/qemu-pebble")
    gcc_bin = Path.join(source_root, "toolchain-linux-x86_64/arm-none-eabi/bin/arm-none-eabi-gcc")

    File.mkdir_p!(Path.dirname(qemu_bin))
    File.mkdir_p!(Path.dirname(gcc_bin))

    File.write!(qemu_bin, """
    #!/bin/sh
    echo qemu-pebble test
    """)

    File.chmod!(qemu_bin, 0o755)
    File.write!(gcc_bin, "#!/bin/sh\n")
    File.chmod!(gcc_bin, 0o755)

    {_, 0} = System.cmd("tar", ["czf", archive_path, "-C", source_root, "."])

    archive_path
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
