defmodule Elmc.Backend.Pebble.Types.Core do
  @moduledoc false

  alias ElmEx.IR.Types.UnionEntry
  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes

  @type draw_kind :: KindTypes.draw_kind()
  @type command_kind :: KindTypes.command_kind()
  @type run_mode :: KindTypes.run_mode()
  @type button_id :: KindTypes.button_id()
  @type accel_axis :: KindTypes.accel_axis()
  @type ui_node_kind :: KindTypes.ui_node_kind()

  @type c_source :: String.t()
  @type c_macro_name :: String.t()
  @type c_symbol :: String.t()
  @type c_type_name :: String.t()
  @type call_target :: String.t()
  @type call_target_list :: [call_target()]
  @type call_target_set :: MapSet.t(call_target())
  @type kind_table :: keyword(non_neg_integer())
  @type draw_kind_table :: [{draw_kind(), non_neg_integer()}]
  @type command_kind_table :: [{command_kind(), non_neg_integer()}]
  @type run_mode_table :: [{run_mode(), non_neg_integer()}]
  @type button_id_table :: [{button_id(), non_neg_integer()}]
  @type accel_axis_table :: [{accel_axis(), non_neg_integer()}]
  @type ui_node_kind_table :: [{ui_node_kind(), non_neg_integer()}]

  @type msg_constructor_pair :: {msg_constructor_name(), non_neg_integer()}
  @type msg_constructor_list :: [msg_constructor_pair()]
  @type msg_constructor_name :: String.t()
  @type union_module :: String.t()
  @type decl_name :: String.t()

  @type msg_constructor_arities :: %{optional(msg_constructor_name()) => non_neg_integer()}

  @type msg_constructor_payload_specs :: %{
          optional(msg_constructor_name()) => String.t() | nil
        }

  @type msg_tag :: integer()
  @type pick_tag_opts :: [fallback: msg_tag()]

  @type entry_module :: String.t()
  @type entry_lifecycle_fn :: :init | :update | :subscriptions | :view | :main

  @type reachability_function_entry :: {union_module(), CCodegenTypes.ir_expr() | nil}
  @type reachability_function_map :: %{call_target() => reachability_function_entry()}

  @type msg_union :: UnionEntry.t() | nil

  @type record_literal_bindings :: %{optional(decl_name()) => CCodegenTypes.ir_expr()}

  @type accel_config :: %{
          required(:samples_per_update) => pos_integer(),
          required(:sampling_hz) => pos_integer()
        }

  @type random_callback_candidate :: msg_constructor_name() | {:tag, msg_tag()}

  @type ir_walk_node :: CCodegenTypes.ir_expr() | ir_map_node() | [ir_walk_node()]
  @type ir_map_node :: %{optional(atom()) => ir_walk_node()}
end
