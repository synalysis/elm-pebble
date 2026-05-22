defmodule Ide.InternalPackages do
  @moduledoc """
  Elm sources bundled with the IDE (Pebble platform stubs, companion protocol) — analogous to
  packages under `elm-stuff`, but kept in `priv/internal_packages` so user projects only contain
  their own modules under `watch/src/`.

  Watch `elm.json` lists these as extra `source-directories` using **absolute** paths so
  projects work regardless of `projects_root` configuration.
  """

  alias Ide.Paths

  @doc false
  @spec shared_elm_abs() :: String.t()
  def shared_elm_abs, do: Paths.bundled_elm_path("shared-elm", "shared/elm")

  @doc false
  @spec pebble_elm_src_abs() :: String.t()
  def pebble_elm_src_abs,
    do: Paths.bundled_elm_path("pebble-watch-src", "packages/elm-pebble/elm-watch/src")

  @doc false
  @spec pebble_companion_core_elm_src_abs() :: String.t()
  def pebble_companion_core_elm_src_abs,
    do:
      Paths.bundled_elm_path(
        "pebble-companion-core-src",
        "packages/elm-pebble-companion-core/src"
      )

  @doc false
  @spec pebble_companion_preferences_elm_src_abs() :: String.t()
  def pebble_companion_preferences_elm_src_abs,
    do:
      Paths.bundled_elm_path(
        "pebble-companion-preferences-src",
        "packages/elm-pebble-companion-preferences/src"
      )

  @doc false
  @spec phone_pebble_stubs_elm_src_abs() :: String.t()
  def phone_pebble_stubs_elm_src_abs,
    do: Paths.priv_path("internal_packages/phone-pebble-stubs/src")

  @doc false
  @spec companion_protocol_elm_src_abs() :: String.t()
  def companion_protocol_elm_src_abs,
    do: Paths.priv_path("internal_packages/companion-protocol/src")

  @doc false
  @spec elm_time_elm_src_abs() :: String.t()
  def elm_time_elm_src_abs, do: Paths.priv_path("internal_packages/elm-time/src")

  @doc false
  @spec elm_random_elm_src_abs() :: String.t()
  def elm_random_elm_src_abs, do: Paths.priv_path("internal_packages/elm-random/src")

  @doc """
  Absolute paths for extra `source-directories` on watch apps (after `"src"`).
  """
  @spec watch_elm_json_extra_source_dirs_abs() :: [String.t()]
  def watch_elm_json_extra_source_dirs_abs do
    [
      pebble_elm_src_abs(),
      companion_protocol_elm_src_abs(),
      elm_time_elm_src_abs(),
      elm_random_elm_src_abs()
    ]
  end

  @doc """
  Absolute paths for extra `source-directories` on watchface templates (after `"src"`).
  """
  @spec watchface_elm_json_extra_source_dirs_abs() :: [String.t()]
  def watchface_elm_json_extra_source_dirs_abs do
    [
      pebble_elm_src_abs(),
      shared_elm_abs(),
      elm_time_elm_src_abs(),
      elm_random_elm_src_abs()
    ]
  end

  @doc """
  Absolute paths for extra `source-directories` on companion phone apps (after `"src"`).
  """
  @spec phone_elm_json_extra_source_dirs_abs() :: [String.t()]
  def phone_elm_json_extra_source_dirs_abs do
    [
      pebble_companion_core_elm_src_abs(),
      pebble_companion_preferences_elm_src_abs(),
      shared_elm_abs(),
      elm_time_elm_src_abs()
    ]
  end
end
