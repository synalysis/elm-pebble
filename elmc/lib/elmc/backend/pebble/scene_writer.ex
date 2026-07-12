defmodule Elmc.Backend.Pebble.SceneWriter do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SceneWriter.{Encode, HeaderEarly, HeaderLate}

  @spec header_early_declarations() :: Types.c_source()
  def header_early_declarations, do: HeaderEarly.body()

  @spec header_struct_decl() :: Types.c_source()
  def header_struct_decl, do: HeaderEarly.struct_decl()

  @spec header_late_declarations() :: Types.c_source()
  def header_late_declarations, do: HeaderLate.body()

  @spec source_implementation() :: Types.c_source()
  def source_implementation, do: Encode.body()
end
