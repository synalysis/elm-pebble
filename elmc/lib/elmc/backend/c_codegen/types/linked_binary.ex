defmodule Elmc.Backend.CCodegen.Types.LinkedBinary do
  @moduledoc """
  Linked ELF/map metadata attached to stack reports after Pebble builds.

  Runtime maps use string keys (`"available"`, `"elf_size"`, …).
  """

  @type elf_size_sections :: %{
          optional(atom()) => non_neg_integer() | String.t() | nil,
          optional(String.t()) => non_neg_integer() | String.t() | nil
        }

  @type wire_symbol_row :: %{
          optional(atom()) => non_neg_integer() | String.t(),
          optional(String.t()) => non_neg_integer() | String.t()
        }

  @typedoc "Linked binary section from `LinkedBinaryReport.from_map/2`."
  @type wire_t :: %{
          optional(:available) => boolean(),
          optional(:map_path) => String.t() | nil,
          optional(:elf_path) => String.t() | nil,
          optional(:elf_size) => elf_size_sections() | nil,
          optional(:top_symbols) => [wire_symbol_row()],
          optional(:elmc_symbols) => [wire_symbol_row()],
          optional(:elmc_text_bytes) => non_neg_integer(),
          optional(atom()) =>
            boolean()
            | String.t()
            | integer()
            | nil
            | [wire_symbol_row()]
            | elf_size_sections(),
          optional(String.t()) =>
            boolean()
            | String.t()
            | integer()
            | nil
            | [wire_symbol_row()]
            | elf_size_sections()
        }

  @type load_error :: Elmc.Types.file_error() | :map_not_found

  @type unavailable :: wire_t()
  @type wire_map :: wire_t()
  @type t :: wire_t()
end
