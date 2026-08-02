defmodule Elmc.TestSupport.HostSmoke do
  @moduledoc false

  @env_key "ELMC_HOST_SMOKE_TEMPLATE"

  @spec templates([String.t()]) :: [String.t()]
  def templates(default) when is_list(default) do
    case System.get_env(@env_key) do
      nil ->
        default

      template when is_binary(template) and template != "" ->
        template
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  @spec default_tea_profile(String.t()) :: map()
  def default_tea_profile(template) do
    cond do
      # Checkerboard of fillRect — no time/circle APIs (see watchface_smoke_screen Main.elm).
      template == "watchface_smoke_screen" ->
        %{require_circles?: false, require_fill_rects?: true, require_time?: false}

      template in ~w(watchface_tangram_time watchface_analog watchface_color_shapes) ->
        %{require_circles?: true, require_fill_rects?: false, require_time?: false}

      template in ~w(watchface_minimal app_minimal) ->
        %{require_circles?: false, require_fill_rects?: false, require_time?: false}

      String.starts_with?(template, "watch_demo_") ->
        %{require_circles?: false, require_fill_rects?: false, require_time?: false}

      # Games are in the host-smoke set for TEA drain/view, but they do not render
      # clock time strings the way watchfaces do.
      String.starts_with?(template, "game_") ->
        %{require_circles?: false, require_fill_rects?: false, require_time?: false}

      true ->
        %{require_circles?: false, require_fill_rects?: false, require_time?: true}
    end
  end

  @spec tea_profiles([String.t()]) :: %{String.t() => map()}
  def tea_profiles(templates) when is_list(templates) do
    Map.new(templates, fn template -> {template, default_tea_profile(template)} end)
  end
end
