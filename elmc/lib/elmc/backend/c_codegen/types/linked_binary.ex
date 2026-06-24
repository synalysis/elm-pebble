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
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type unavailable :: wire_t()
  @type wire_map :: wire_t()
  @type t :: wire_t()
end
