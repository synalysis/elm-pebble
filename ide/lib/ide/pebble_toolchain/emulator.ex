defmodule Ide.PebbleToolchain.Emulator do
  @moduledoc false

  alias Ide.PebbleToolchain.Command
  alias Ide.PebbleToolchain.Types
  alias Ide.WatchModels

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type command_result :: Types.command_result()
  @type emulator_control_params :: Types.emulator_control_params()
  @type toolchain_error :: Types.toolchain_error()

  @doc """
  Runs `pebble wipe` and then `pebble install --emulator` for a specific `.pbw` artifact.
  """
  @spec run_emulator(project_slug(), opts()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def run_emulator(_project_slug, opts) do
    with :ok <- ensure_external_emulator_allowed() do
      do_run_emulator(opts)
    end
  end

  @doc """
  Stops running Pebble emulator processes via `pebble kill`.
  """
  @spec stop_emulator(project_slug(), opts()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def stop_emulator(_project_slug, opts \\ []) do
    with :ok <- ensure_external_emulator_allowed() do
      do_stop_emulator(opts)
    end
  end

  @doc """
  Captures a short `pebble logs --emulator` snapshot for the given target.
  """
  @spec emulator_logs_snapshot(String.t(), String.t(), pos_integer()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def emulator_logs_snapshot(emulator_target, cwd, seconds)
      when is_binary(emulator_target) and is_binary(cwd) and is_integer(seconds) and
             seconds > 0 do
    capture_emulator_logs_snapshot(emulator_target, cwd, seconds)
  end

  @doc """
  Runs `pebble screenshot` to capture emulator output into a file.
  """
  @spec run_screenshot(project_slug(), String.t(), String.t()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def run_screenshot(_project_slug, output_path, emulator_target) do
    with :ok <- ensure_external_emulator_allowed() do
      Command.run_pebble_with_timeout(
        ["screenshot", "--emulator", emulator_target, "--no-open", output_path],
        15,
        []
      )
    end
  end

  @doc """
  Runs a Pebble SDK emulator control command for an already running external emulator.
  """
  @spec run_emulator_control(project_slug(), String.t(), emulator_control_params()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def run_emulator_control(_project_slug, emulator_target, %{} = params) do
    with :ok <- ensure_external_emulator_allowed(),
         {:ok, args} <- emulator_control_args(emulator_target, params) do
      Command.run_pebble_with_timeout(args, 10, [])
    end
  end

  @doc """
  Returns supported emulator/watch targets for capture and install.
  """
  @spec supported_emulator_targets() :: [String.t()]
  def supported_emulator_targets do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_targets, WatchModels.ordered_ids())
  end

  defp do_run_emulator(opts) do
    emulator_target = Keyword.get(opts, :emulator_target, configured_emulator_target())
    package_path = Keyword.get(opts, :package_path)
    install_timeout_seconds = max(Keyword.get(opts, :install_timeout_seconds, 120), 30)
    owner = Ide.Emulator.SlotLimiter.external_owner(emulator_target)

    with {:ok, ^owner} <-
           Ide.Emulator.SlotLimiter.acquire(owner,
             kind: :external,
             platform: emulator_target,
             timeout: emulator_slot_acquire_timeout(opts)
           ),
         {:ok, package_path} <- normalize_package_path(package_path),
         {:ok, cwd} <- {:ok, Path.dirname(package_path)},
         {:ok, install_result} <-
           install_on_emulator(cwd, emulator_target, package_path, install_timeout_seconds) do
      {:ok, attach_emulator_logs(install_result, emulator_target, cwd, opts)}
    else
      {:error, :timeout} = err ->
        err

      {:error, reason} ->
        Ide.Emulator.SlotLimiter.release(owner)
        {:error, reason}
    end
  end

  defp do_stop_emulator(opts) do
    emulator_target = Keyword.get(opts, :emulator_target)
    force? = Keyword.get(opts, :force, false)

    args =
      if force? do
        ["kill", "--force"]
      else
        ["kill"]
      end

    result = Command.run_pebble_with_timeout(args, Keyword.get(opts, :timeout_seconds, 10), opts)
    release_external_emulator_slots(emulator_target, force?)
    result
  end

  defp release_external_emulator_slots(emulator_target, force?) do
    cond do
      force? ->
        Ide.Emulator.SlotLimiter.release_all_external()

      is_binary(emulator_target) ->
        Ide.Emulator.SlotLimiter.release_external(emulator_target)

      true ->
        :ok
    end
  end

  defp emulator_slot_acquire_timeout(opts) do
    Keyword.get(opts, :slot_acquire_timeout_ms) ||
      Application.get_env(:ide, Ide.Emulator.SlotLimiter, [])
      |> Keyword.get(:acquire_timeout_ms, 600_000)
  end

  @spec install_on_emulator(String.t(), String.t(), String.t(), pos_integer()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  defp install_on_emulator(cwd, emulator_target, package_path, timeout_seconds)
       when is_binary(cwd) and is_binary(emulator_target) and is_binary(package_path) and
              is_integer(timeout_seconds) and timeout_seconds > 0 do
    with {:ok, wipe_result} <-
           Command.run_pebble_with_timeout(["wipe"], timeout_seconds, cwd: cwd),
         :ok <- ensure_successful_wipe(wipe_result) do
      Command.run_pebble_with_timeout(
        emulator_install_args(emulator_target, package_path),
        timeout_seconds,
        cwd: cwd
      )
    end
  end

  @spec ensure_successful_wipe(command_result()) :: :ok | {:error, toolchain_error()}
  defp ensure_successful_wipe(%{status: :ok}), do: :ok
  defp ensure_successful_wipe(result), do: {:error, {:pebble_wipe_failed, result}}

  @spec emulator_install_args(String.t(), String.t()) :: [String.t()]
  defp emulator_install_args(emulator_target, package_path) do
    ["install", "--emulator", emulator_target]
    |> maybe_append_emulator_install_throttle()
    |> Kernel.++([package_path])
  end

  @spec maybe_append_emulator_install_throttle([String.t()]) :: [String.t()]
  defp maybe_append_emulator_install_throttle(args) do
    case configured_emulator_install_throttle() do
      nil -> args
      throttle -> args ++ ["--throttle=#{throttle}"]
    end
  end

  @spec configured_emulator_install_throttle() :: String.t() | nil
  defp configured_emulator_install_throttle do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_install_throttle_seconds, 0.004)
    |> case do
      nil ->
        nil

      throttle when is_binary(throttle) ->
        String.trim(throttle)

      throttle when is_number(throttle) and throttle > 0 ->
        :erlang.float_to_binary(throttle / 1, decimals: 3)

      _ ->
        nil
    end
    |> case do
      "" -> nil
      throttle -> throttle
    end
  end

  @spec attach_emulator_logs(command_result(), String.t(), String.t(), opts()) ::
          command_result()
  defp attach_emulator_logs(result, emulator_target, cwd, opts) do
    logs_seconds = Keyword.get(opts, :logs_snapshot_seconds, 4)

    case capture_emulator_logs_snapshot(emulator_target, cwd, logs_seconds) do
      {:ok, logs_result} ->
        summary = """

        --- emulator logs snapshot (#{logs_seconds}s) ---
        command: #{logs_result.command}
        #{format_logs_snapshot_exit(logs_result.exit_code, logs_seconds)}

        #{String.trim(logs_result.output)}
        """

        %{result | output: String.trim(result.output) <> summary}

      {:error, reason} ->
        summary = """

        --- emulator logs snapshot ---
        unavailable: #{inspect(reason)}
        """

        %{result | output: String.trim(result.output) <> summary}
    end
  end

  @spec capture_emulator_logs_snapshot(String.t(), String.t(), pos_integer()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  defp capture_emulator_logs_snapshot(emulator_target, cwd, seconds)
       when is_binary(emulator_target) and is_integer(seconds) and seconds > 0 do
    with {:ok, pebble_bin} <- Command.pebble_bin() do
      timeout_bin = System.find_executable("timeout")

      cond do
        is_nil(timeout_bin) ->
          {:error, :timeout_utility_not_found}

        true ->
          args = [
            "#{seconds}s",
            pebble_bin,
            "logs",
            "--emulator",
            emulator_target,
            "--no-color"
          ]

          env = Command.pebble_command_env(args)

          {output, exit_code} =
            System.cmd(timeout_bin, args, cd: cwd, stderr_to_stdout: true, env: env)

          {:ok,
           %{
             status: if(expected_logs_snapshot_exit?(exit_code), do: :ok, else: :error),
             command: Enum.join([timeout_bin | args], " "),
             output: output,
             exit_code: exit_code,
             cwd: cwd
           }}
      end
    end
  rescue
    error -> {:error, error}
  end

  defp format_logs_snapshot_exit(124, seconds),
    do: "exit_code: 124 (expected timeout after #{seconds}s log snapshot)"

  defp format_logs_snapshot_exit(exit_code, _seconds), do: "exit_code: #{exit_code}"

  defp expected_logs_snapshot_exit?(exit_code), do: exit_code in [0, 124]

  @spec emulator_control_args(String.t(), emulator_control_params()) ::
          {:ok, [String.t()]} | {:error, toolchain_error()}
  defp emulator_control_args(emulator_target, %{"control" => "button"} = params) do
    action = params |> Map.get("action", "click") |> normalize_button_action()
    button = params |> Map.get("button") |> normalize_emulator_button()

    case {action, button} do
      {{:ok, action}, {:ok, button}} ->
        {:ok, ["emu-button", "--emulator", emulator_target, action, button]}

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp emulator_control_args(emulator_target, %{"control" => "battery"} = params) do
    percent = params |> Map.get("percent", 80) |> normalize_percent()
    charging? = truthy?(Map.get(params, "charging"))

    case percent do
      {:ok, percent} ->
        args = [
          "emu-battery",
          "--emulator",
          emulator_target,
          "--percent",
          Integer.to_string(percent)
        ]

        {:ok, if(charging?, do: args ++ ["--charging"], else: args)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emulator_control_args(emulator_target, %{"control" => "bluetooth"} = params) do
    connected = if truthy?(Map.get(params, "connected")), do: "yes", else: "no"
    {:ok, ["emu-bt-connection", "--emulator", emulator_target, "--connected", connected]}
  end

  defp emulator_control_args(emulator_target, %{"control" => "tap"} = params) do
    direction = params |> Map.get("direction", "z+") |> normalize_tap_direction()

    case direction do
      {:ok, direction} ->
        {:ok, ["emu-tap", "--emulator", emulator_target, "--direction", direction]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emulator_control_args(emulator_target, %{"control" => "time_format"} = params) do
    format = if truthy?(Map.get(params, "enabled")), do: "24h", else: "12h"
    {:ok, ["emu-time-format", "--emulator", emulator_target, "--format", format]}
  end

  defp emulator_control_args(emulator_target, %{"control" => "timeline_quick_view"} = params) do
    value = if truthy?(Map.get(params, "enabled")), do: "on", else: "off"
    {:ok, ["emu-set-timeline-quick-view", "--emulator", emulator_target, value]}
  end

  defp emulator_control_args(emulator_target, %{"control" => "set_time"} = params) do
    case Map.get(params, "time") do
      time when is_binary(time) and time != "" ->
        {:ok, ["emu-set-time", "--emulator", emulator_target, time]}

      _ ->
        {:error, :invalid_set_time}
    end
  end

  defp emulator_control_args(emulator_target, %{"control" => "compass"} = params) do
    with {:ok, heading} <- normalize_compass_heading(Map.get(params, "heading", "0")) do
      calibrated =
        if truthy?(Map.get(params, "valid", true)), do: "--calibrated", else: "--uncalibrated"

      {:ok,
       [
         "emu-compass",
         "--emulator",
         emulator_target,
         "--heading",
         Integer.to_string(heading),
         calibrated
       ]}
    end
  end

  defp emulator_control_args(_emulator_target, params),
    do: {:error, {:unsupported_emulator_control, Map.get(params, "control")}}

  defp normalize_button_action(action) when action in ["click", "push", "release"],
    do: {:ok, action}

  defp normalize_button_action(_), do: {:error, :invalid_button_action}

  defp normalize_emulator_button(button) when button in ["back", "up", "select", "down"],
    do: {:ok, button}

  defp normalize_emulator_button(_), do: {:error, :invalid_button}

  defp normalize_tap_direction(direction) when direction in ["x+", "x-", "y+", "y-", "z+", "z-"],
    do: {:ok, direction}

  defp normalize_tap_direction(_), do: {:error, :invalid_tap_direction}

  defp normalize_percent(value) when is_integer(value) and value in 0..100, do: {:ok, value}

  defp normalize_percent(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> normalize_percent(int)
      _ -> {:error, :invalid_percent}
    end
  end

  defp normalize_percent(_), do: {:error, :invalid_percent}

  defp normalize_compass_heading(value) when is_integer(value) and value in 0..359,
    do: {:ok, value}

  defp normalize_compass_heading(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> normalize_compass_heading(int)
      _ -> {:error, :invalid_compass_heading}
    end
  end

  defp normalize_compass_heading(_), do: {:error, :invalid_compass_heading}

  defp truthy?(values) when is_list(values), do: Enum.any?(values, &truthy?/1)
  defp truthy?(value), do: value in [true, "true", "1", 1, "yes", "on"]

  @spec configured_emulator_target() :: String.t()
  defp configured_emulator_target do
    Application.get_env(:ide, Ide.PebbleToolchain, [])
    |> Keyword.get(:emulator_target, "basalt")
  end

  @spec normalize_package_path(String.t() | nil) ::
          {:ok, String.t()} | {:error, toolchain_error()}
  defp normalize_package_path(path) when is_binary(path) do
    abs = Path.expand(path)

    cond do
      path == "" ->
        {:error, :package_path_required}

      not File.exists?(abs) ->
        {:error, {:package_path_not_found, abs}}

      not String.ends_with?(String.downcase(abs), ".pbw") ->
        {:error, {:package_path_not_pbw, abs}}

      true ->
        {:ok, abs}
    end
  end

  defp normalize_package_path(_), do: {:error, :package_path_required}

  defp ensure_external_emulator_allowed do
    if Ide.Auth.public_mode?() do
      {:error, :external_emulator_disabled}
    else
      :ok
    end
  end
end
