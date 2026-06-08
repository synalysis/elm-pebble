defmodule Elmc.Backend.CCodegen.SpecialValues do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Core
  alias Elmc.Backend.CCodegen.SpecialValues.Dispatcher

  @spec generated_draw_kind_macro(atom() | integer()) :: String.t()
  defdelegate generated_draw_kind_macro(kind), to: Core

  @spec msg_tag_param(term()) :: term()
  defdelegate msg_tag_param(expr), to: Core

  @spec subscription_to_msg_params([term()]) :: [term()]
  defdelegate subscription_to_msg_params(args), to: Core

  @spec encoded_sub_as_tuple(term(), [term()]) :: term()
  defdelegate encoded_sub_as_tuple(mask_expr, args), to: Core

  @spec encoded_cmd_as_tuple(term(), [term()]) :: term()
  defdelegate encoded_cmd_as_tuple(kind_expr, args), to: Core

  @spec normalize_special_target(String.t()) :: String.t()
  defdelegate normalize_special_target(target), to: Core

  @spec constructor_tag(String.t()) :: integer()
  defdelegate constructor_tag(name), to: Core

  @spec field_access_expr(map(), String.t()) :: term()
  defdelegate field_access_expr(arg_expr, field), to: Core

  @spec special_value_from_target(String.t(), [term()]) :: term()
  defdelegate special_value_from_target(target, args), to: Dispatcher
end
