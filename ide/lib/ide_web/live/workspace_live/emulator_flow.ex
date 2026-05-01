defmodule IdeWeb.WorkspaceLive.EmulatorFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias IdeWeb.WorkspaceLive.ResourcesFlow

  def group_screenshots(shots), do: ResourcesFlow.group_screenshots(shots)

  @spec render_capture_all_progress(term()) :: term()
  def render_capture_all_progress({:phase, message}) when is_binary(message), do: message

  def render_capture_all_progress({:target, target, :cleanup_before}),
    do: "[#{target}] Cleaning previous emulator..."

  def render_capture_all_progress({:target, target, :installing}),
    do: "[#{target}] Installing app..."

  def render_capture_all_progress({:target, target, :capturing}),
    do: "[#{target}] Capturing screenshot..."

  def render_capture_all_progress({:target, target, :capture_attempt, attempt, total}),
    do: "[#{target}] Capture attempt #{attempt}/#{total}..."

  def render_capture_all_progress({:target, target, :capture_retry, attempt, total, reason}),
    do: "[#{target}] Attempt #{attempt}/#{total} failed: #{inspect(reason)}"

  def render_capture_all_progress({:target, target, :ok}), do: "[#{target}] Screenshot captured."

  def render_capture_all_progress({:target, target, :captured, _screenshot}),
    do: "[#{target}] Screenshot added to gallery."

  def render_capture_all_progress({:target, target, :cleanup_after}),
    do: "[#{target}] Closing emulator..."

  def render_capture_all_progress({:target, target, :cleanup_error, _phase, reason}),
    do: "[#{target}] Cleanup warning: #{inspect(reason)}"

  def render_capture_all_progress({:target, target, :error, reason}),
    do: "[#{target}] Failed: #{inspect(reason)}"

  def render_capture_all_progress({:close, {:ok, _result}}), do: "Emulators stopped."

  def render_capture_all_progress({:close, {:error, reason}}),
    do: "Could not stop emulators: #{inspect(reason)}"

  def render_capture_all_progress(_), do: "Working..."

  @spec update_capture_target_statuses(term(), term()) :: term()
  def update_capture_target_statuses(statuses, {:target, target, :cleanup_before}),
    do: Map.put(statuses, target, "cleaning previous emulator")

  def update_capture_target_statuses(statuses, {:target, target, :installing}),
    do: Map.put(statuses, target, "installing")

  def update_capture_target_statuses(statuses, {:target, target, :capturing}),
    do: Map.put(statuses, target, "capturing")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :capture_attempt, attempt, total}
      ),
      do: Map.put(statuses, target, "capture attempt #{attempt}/#{total}")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :capture_retry, attempt, total, _reason}
      ),
      do: Map.put(statuses, target, "retrying after attempt #{attempt}/#{total}")

  def update_capture_target_statuses(statuses, {:target, target, :ok}),
    do: Map.put(statuses, target, "done")

  def update_capture_target_statuses(statuses, {:target, target, :cleanup_after}),
    do: keep_capture_terminal_status(statuses, target, "closing emulator")

  def update_capture_target_statuses(
        statuses,
        {:target, target, :cleanup_error, _phase, reason}
      ),
      do: keep_capture_terminal_status(statuses, target, "cleanup warning: #{inspect(reason)}")

  def update_capture_target_statuses(statuses, {:target, target, :error, reason}),
    do: Map.put(statuses, target, "error: #{inspect(reason)}")

  def update_capture_target_statuses(statuses, {:phase, message}) when is_binary(message) do
    case Regex.run(~r/^\[(\d+)\/(\d+)\]\s+([a-z0-9_-]+)/i, message) do
      [_, _idx, _total, target] -> Map.put(statuses, target, "running")
      _ -> statuses
    end
  end

  def update_capture_target_statuses(statuses, _msg), do: statuses

  @spec maybe_merge_capture_progress_screenshot(term(), term()) :: term()
  def maybe_merge_capture_progress_screenshot(socket, {:target, _target, :captured, screenshot})
      when is_map(screenshot) do
    shots = upsert_screenshot(socket.assigns.screenshots || [], screenshot)

    socket
    |> assign(:screenshots, shots)
    |> assign(:screenshot_groups, group_screenshots(shots))
  end

  def maybe_merge_capture_progress_screenshot(socket, _msg), do: socket

  @spec upsert_screenshot(term(), term()) :: term()
  def upsert_screenshot(existing, screenshot) do
    key = screenshot_identity(screenshot)

    existing
    |> Enum.reject(fn item -> screenshot_identity(item) == key end)
    |> Kernel.++([screenshot])
    |> Enum.sort_by(&screenshot_sort_key/1, :desc)
  end

  @spec screenshot_identity(term()) :: term()
  def screenshot_identity(item) when is_map(item) do
    cond do
      is_binary(item[:absolute_path]) and item[:absolute_path] != "" ->
        {:path, item[:absolute_path]}

      is_binary(item[:filename]) and item[:filename] != "" ->
        {:filename, item[:filename]}

      true ->
        {:fallback, inspect(item)}
    end
  end

  @spec screenshot_sort_key(term()) :: term()
  def screenshot_sort_key(item) when is_map(item) do
    case item[:captured_at] do
      %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
      %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
      other when is_binary(other) -> other
      _ -> ""
    end
  end

  @spec keep_capture_terminal_status(term(), term(), term()) :: term()
  def keep_capture_terminal_status(statuses, target, next_status) do
    case Map.get(statuses, target) do
      "done" -> statuses
      "error: " <> _ = error_status -> Map.put(statuses, target, error_status)
      _ -> Map.put(statuses, target, next_status)
    end
  end

  @spec merge_capture_all_result_statuses(term(), term()) :: term()
  def merge_capture_all_result_statuses(statuses, result) when is_map(result) do
    results = Map.get(result, :results, [])

    Enum.reduce(results, statuses, fn
      {target, {:ok, _shot}}, acc ->
        Map.put(acc, target, "done")

      {target, {:error, reason}}, acc ->
        Map.put(acc, target, "error: #{inspect(reason)}")

      _other, acc ->
        acc
    end)
  end

  def merge_capture_all_result_statuses(statuses, _result), do: statuses

  @spec emulator_install_error_message(term()) :: term()
  def emulator_install_error_message(:package_path_required) do
    "No installable artifact selected. Generate a `.pbw` artifact first, then install it to the emulator."
  end

  def emulator_install_error_message({:package_path_not_found, path}) do
    "Selected artifact was not found: #{path}"
  end

  def emulator_install_error_message({:package_path_not_pbw, path}) do
    "Selected artifact is not a `.pbw` file: #{path}"
  end

  def emulator_install_error_message(reason) do
    "Emulator install failed before execution: #{inspect(reason)}"
  end
end
