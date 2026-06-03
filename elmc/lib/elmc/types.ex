defmodule Elmc.Types do
  @moduledoc """
  Shared types used across elmc packages.
  """

  @type file_error :: File.posix()

  @type module_name :: String.t()
  @type function_name :: String.t()

  @type compile_options :: %{
          optional(:entry_module) => module_name(),
          optional(:out_dir) => String.t() | nil,
          optional(:runtime_dir) => String.t(),
          optional(:strip_dead_code) => boolean(),
          optional(:prune_runtime) => boolean(),
          optional(:prune_native_wrappers) => boolean(),
          optional(:direct_render_only) => boolean(),
          optional(:pebble_int32) => boolean()
        }
end
