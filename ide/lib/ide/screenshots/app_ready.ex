defmodule Ide.Screenshots.AppReady do
  @moduledoc false

  @type target_type :: String.t()
  @type decision :: :wait | :ready | :dismiss_back | :open_app

  @type snapshot :: %{
          required(:elapsed_ms) => non_neg_integer(),
          required(:saw_change?) => boolean(),
          required(:stable?) => boolean(),
          required(:dismissed_back?) => boolean(),
          required(:opened_app?) => boolean(),
          required(:target_type) => target_type(),
          required(:min_ms) => non_neg_integer(),
          required(:dismiss_ms) => non_neg_integer(),
          required(:open_app_ms) => non_neg_integer(),
          required(:stuck_ms) => non_neg_integer()
        }

  @spec app_target_type?(target_type()) :: boolean()
  def app_target_type?(target_type) when target_type in ["app", "watchapp"], do: true
  def app_target_type?(_target_type), do: false

  @doc """
  After `pebble install` the firmware still shows the factory “Install an app”
  / install-progress overlay until the PBW’s first frame is composed.

  Do not treat the first boot → launcher transition as “app ready”. Press
  Back once to dismiss the overlay, then keep a *stable* later frame
  (overlay gone, or a watchface that finished its first paint). A static
  face that never changes is accepted after `stuck_ms`.
  """
  @spec decision(snapshot()) :: decision()
  def decision(%{
        elapsed_ms: elapsed,
        saw_change?: saw_change?,
        stable?: stable?,
        dismissed_back?: dismissed_back?,
        opened_app?: opened_app?,
        target_type: target_type,
        min_ms: min_ms,
        dismiss_ms: dismiss_ms,
        open_app_ms: open_app_ms,
        stuck_ms: stuck_ms
      })
      when is_integer(elapsed) and elapsed >= 0 do
    cond do
      saw_change? and dismissed_back? and stable? and elapsed >= min_ms ->
        :ready

      elapsed >= stuck_ms ->
        :ready

      not dismissed_back? and elapsed >= dismiss_ms ->
        :dismiss_back

      not saw_change? and dismissed_back? and not opened_app? and app_target_type?(target_type) and
          elapsed >= open_app_ms ->
        :open_app

      true ->
        :wait
    end
  end

  @spec png_digest(binary()) :: binary()
  def png_digest(png) when is_binary(png) do
    :crypto.hash(:sha256, png)
  end
end
