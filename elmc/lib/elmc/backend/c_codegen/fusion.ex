defmodule Elmc.Backend.CCodegen.Fusion do
  @moduledoc false

  alias Elmc.Backend.Plan.Fusion.Registry

  defdelegate providers(), to: Registry
  defdelegate try_emit(module_name, name, expr, decl_map), to: Registry
  defdelegate reset_caches!(), to: Registry
  defdelegate compact_list_field_keys(module_name, name, expr, decl_map), to: Registry
  defdelegate register_rc_native_arg_kinds(module, name, kinds), to: Registry
  defdelegate rc_native_fusion_arg_kinds(key), to: Registry
  defdelegate register_union_int_lut(module, name, lut), to: Registry
  defdelegate union_int_lut_lookup(key, union_tag), to: Registry
  defdelegate infer_native_tag_fusion_arg_kinds(c_body, decl), to: Registry
  defdelegate runtime_callees(module_name, name, expr, decl_map), to: Registry
  defdelegate rc_native_fusion?(module_name, name, expr, decl_map), to: Registry
end
