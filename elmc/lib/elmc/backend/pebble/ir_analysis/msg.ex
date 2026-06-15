defmodule Elmc.Backend.Pebble.IRAnalysis.Msg do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.IRAnalysis.Msg.{Constructors, Lookup, ModuleQuery}

  @spec constructors(IR.t(), Types.entry_module()) :: Types.msg_constructor_list()
  defdelegate constructors(ir, entry_module), to: Constructors

  @spec constructor_arities(IR.t(), Types.entry_module()) :: Types.msg_constructor_arities()
  defdelegate constructor_arities(ir, entry_module), to: Constructors

  @spec constructor_payload_specs(IR.t(), Types.entry_module()) ::
          Types.msg_constructor_payload_specs()
  defdelegate constructor_payload_specs(ir, entry_module), to: Constructors

  @spec phone_to_watch_target(
          Types.msg_constructor_list(),
          Types.msg_constructor_payload_specs()
        ) :: Types.msg_tag()
  defdelegate phone_to_watch_target(msg_constructors, payload_specs), to: Lookup

  @spec constructor_name_for_tag(Types.msg_constructor_list(), non_neg_integer()) ::
          Types.msg_constructor_name() | nil
  defdelegate constructor_name_for_tag(constructors, tag), to: Lookup

  @spec pick_tag(
          Types.msg_constructor_list(),
          [Types.msg_constructor_name()],
          Types.pick_tag_opts()
        ) :: Types.msg_tag()
  defdelegate pick_tag(msg_constructors, names, opts \\ []), to: Lookup

  @spec has_view?(IR.t(), Types.entry_module()) :: boolean()
  defdelegate has_view?(ir, entry_module), to: ModuleQuery

  @spec union_constructors(
          IR.t(),
          Types.union_module(),
          Types.decl_name()
        ) :: Types.msg_constructor_list()
  defdelegate union_constructors(ir, module_name, union_name), to: ModuleQuery
end
