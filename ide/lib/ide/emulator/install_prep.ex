defmodule Ide.Emulator.InstallPrep do
  @moduledoc false

  alias Ide.Emulator.Session

  @default_install_min_ms_after_boot_by_platform %{
    "emery" => 8_000,
    "flint" => 6_000,
    "gabbro" => 6_000
  }

  @default_install_reuse_settle_extra_by_platform %{
    "emery" => 500,
    "flint" => 500,
    "gabbro" => 500
  }

  @doc """
  Returns true when QEMU should be reset before the next PBW install instead of reusing
  the running session.
  """
  @spec reset_needed?(map()) :: boolean()
  def reset_needed?(state) when is_map(state) do
    reuse_window_ms = config(:install_reuse_boot_window_ms, 120_000)

    cond do
      not qemu_and_router_healthy?(state) ->
        true

      now_ms() - Map.get(state, :last_boot_ms, 0) > reuse_window_ms ->
        true

      true ->
        false
    end
  end

  def reset_needed?(_state), do: true

  @doc """
  PBWInstaller keyword options for the given platform.
  """
  @spec pacing_opts(String.t()) :: keyword()
  def pacing_opts(platform) when is_binary(platform) do
    base = [
      timeout_ms: config(:pbw_request_timeout_ms, 60_000),
      install_timeout_ms: config(:pbw_install_timeout_ms, 180_000),
      install_retries: config(:pbw_install_retries, 3),
      install_retry_delay_ms: config(:pbw_install_retry_delay_ms, 2_000),
      post_install_probe_timeout_ms: 1_000
    ]

    Keyword.merge(base, platform_putbytes_pacing(platform))
  end

  @doc """
  Sleeps until minimum time since boot and reuse settle have elapsed before PutBytes.
  """
  @spec wait_before_reuse_install(map()) :: :ok
  def wait_before_reuse_install(state) when is_map(state) do
    platform = Map.get(state, :platform, "")
    last_boot_ms = Map.get(state, :last_boot_ms, 0)

    :ok = ensure_min_time_since_boot(platform, last_boot_ms)

    settle_ms = reuse_settle_ms(state)
    if settle_ms > 0, do: Process.sleep(settle_ms)

    :ok
  end

  @spec min_ms_after_boot(String.t()) :: non_neg_integer()
  def min_ms_after_boot(platform) when is_binary(platform) do
    config(
      :install_min_ms_after_boot_by_platform,
      @default_install_min_ms_after_boot_by_platform
    )
    |> Map.get(platform, config(:install_min_ms_after_boot, 5_000))
  end

  @spec qemu_and_router_healthy?(map()) :: boolean()
  def qemu_and_router_healthy?(state) when is_map(state) do
    live_pid?(Map.get(state, :qemu_pid)) and live_pid?(Map.get(state, :protocol_router_pid)) and
      Session.tcp_port_open?(Map.get(state, :bt_port, 0))
  end

  def qemu_and_router_healthy?(_state), do: false

  defp ensure_min_time_since_boot(platform, last_boot_ms) do
    required = min_ms_after_boot(platform)
    elapsed = now_ms() - last_boot_ms

    if elapsed < required do
      Process.sleep(required - elapsed)
    end

    :ok
  end

  defp reuse_settle_ms(state) do
    base = config(:install_reuse_settle_ms, 500)
    platform = Map.get(state, :platform, "")

    extra =
      config(
        :install_reuse_settle_extra_by_platform,
        @default_install_reuse_settle_extra_by_platform
      )
      |> Map.get(platform, 0)

    base + extra
  end

  # Larger PBWs on snowy-class QEMU machines need smaller PutBytes chunks and more
  # time between chunks so the Bluetooth stack keeps up during the binary phase (~5% UI).
  defp platform_putbytes_pacing(platform) when platform in ["emery", "flint", "gabbro"] do
    [
      chunk_size: config(:pbw_chunk_size, 256),
      chunk_delay_ms: config(:pbw_chunk_delay_ms, 20),
      part_delay_ms: config(:pbw_part_delay_ms, 300),
      putbytes_retries: config(:pbw_putbytes_retries, 3)
    ]
  end

  defp platform_putbytes_pacing(_platform) do
    [
      chunk_size: config(:pbw_chunk_size, 500),
      chunk_delay_ms: config(:pbw_chunk_delay_ms, 10)
    ]
  end

  defp live_pid?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp live_pid?(_pid), do: false

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp config(key, default),
    do: Application.get_env(:ide, Session, []) |> Keyword.get(key, default)
end
