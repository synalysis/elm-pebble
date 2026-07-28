defmodule Elmc.TestSupport.HostSmoke do
  @moduledoc false

  @env_key "ELMC_HOST_SMOKE_TEMPLATE"

  @spec templates([String.t()]) :: [String.t()]
  def templates(default) when is_list(default) do
    case System.get_env(@env_key) do
      nil -> default
      template when is_binary(template) and template != "" -> [template]
    end
  end

  @spec default_tea_profile(String.t()) :: map()
  def default_tea_profile(template) do
    cond do
      template in ~w(watchface_tangram_time watchface_analog watchface_color_shapes watchface_smoke_screen) ->
        %{require_circles?: true, require_time?: false}

      template in ~w(watchface_minimal app_minimal) ->
        %{require_circles?: false, require_time?: false}

      String.starts_with?(template, "watch_demo_") ->
        %{require_circles?: false, require_time?: false}

      true ->
        %{require_circles?: false, require_time?: true}
    end
  end

  @spec tea_profiles([String.t()]) :: %{String.t() => map()}
  def tea_profiles(templates) when is_list(templates) do
    Map.new(templates, fn template -> {template, default_tea_profile(template)} end)
  end
end
