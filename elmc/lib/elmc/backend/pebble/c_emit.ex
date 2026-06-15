defmodule Elmc.Backend.Pebble.CEmit do
  @moduledoc false

  alias Elmc.Backend.Pebble.{Types, Util}

  @spec constructor_tag_macros(Types.c_macro_name(), Types.msg_constructor_list()) ::
          Types.c_source()
  def constructor_tag_macros(prefix, constructors) do
    constructors
    |> Enum.map_join("\n", fn {name, tag} ->
      "#define #{prefix}_#{Util.macro_name(name)} #{tag}"
    end)
  end

  @spec c_enum(Types.c_type_name(), Types.c_macro_name(), Types.kind_table()) :: Types.c_source()
  def c_enum(type_name, prefix, entries) do
    members =
      entries
      |> Enum.map_join(",\n", fn {name, value} ->
        "  #{prefix}_#{Util.macro_name(Atom.to_string(name))} = #{value}"
      end)

    """
    typedef enum {
    #{members}
    } #{type_name};
    """
  end
end
