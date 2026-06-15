defmodule Elmc.Backend.Pebble.IRAnalysis do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.IRAnalysis.{Build, Msg, RandomGenerate}

  @spec msg_constructors(IR.t(), Types.entry_module()) :: Types.msg_constructor_list()
  defdelegate msg_constructors(ir, entry_module), to: Msg, as: :constructors

  @spec msg_constructor_arities(IR.t(), Types.entry_module()) :: Types.msg_constructor_arities()
  defdelegate msg_constructor_arities(ir, entry_module), to: Msg, as: :constructor_arities

  @spec msg_constructor_payload_specs(IR.t(), Types.entry_module()) ::
          Types.msg_constructor_payload_specs()
  defdelegate msg_constructor_payload_specs(ir, entry_module),
    to: Msg,
    as: :constructor_payload_specs

  @spec phone_to_watch_msg_target(
          Types.msg_constructor_list(),
          Types.msg_constructor_payload_specs()
        ) :: Types.msg_tag()
  defdelegate phone_to_watch_msg_target(msg_constructors, payload_specs),
    to: Msg,
    as: :phone_to_watch_target

  @spec constructor_name_for_tag(Types.msg_constructor_list(), non_neg_integer()) ::
          Types.msg_constructor_name() | nil
  defdelegate constructor_name_for_tag(constructors, tag), to: Msg

  @spec has_view?(IR.t(), Types.entry_module()) :: boolean()
  defdelegate has_view?(ir, entry_module), to: Msg

  @spec pick_tag(
          Types.msg_constructor_list(),
          [Types.msg_constructor_name()],
          Types.pick_tag_opts()
        ) :: Types.msg_tag()
  def pick_tag(msg_constructors, names, opts \\ []),
    do: Msg.pick_tag(msg_constructors, names, opts)

  @spec union_constructors(
          IR.t(),
          Types.union_module(),
          Types.decl_name()
        ) :: Types.msg_constructor_list()
  defdelegate union_constructors(ir, module_name, union_name), to: Msg

  @spec analyze(IR.t(), Types.entry_module()) :: Types.shim_analysis()
  defdelegate analyze(ir, entry_module), to: Build

  @spec random_generate_target_tag(IR.t(), Types.msg_constructor_list()) :: Types.msg_tag()
  def random_generate_target_tag(ir, msg_constructors),
    do: RandomGenerate.target_tag(ir, msg_constructors)
end
