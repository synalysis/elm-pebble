defmodule Elmc.Backend.Plan.Lower.Types do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Types, as: PlanTypes

  @type ir_expr :: CCodegenTypes.ir_expr()
  @type ir_case_expr :: CCodegenTypes.ir_case_expr()
  @type pattern :: CCodegenTypes.pattern()
  @type case_branch :: CCodegenTypes.case_branch()
  @type case_branches :: CCodegenTypes.case_branches()
  @type int_case_branches :: CCodegenTypes.int_case_branches()
  @type ir_record_field :: CCodegenTypes.ir_record_field()
  @type ir_record_fields :: CCodegenTypes.ir_record_fields()
  @type function_decl :: CCodegenTypes.function_decl()
  @type function_decl_map :: CCodegenTypes.function_decl_map()
  @type special_value_args :: CCodegenTypes.special_value_args()
  @type special_value_expr :: CCodegenTypes.ir_expr() | nil

  @type result_slot :: PlanTypes.reg() | :fn_out | :branch_out | nil

  @type compile_result :: {:ok, result_slot(), Builder.t()} | :unsupported
  @type compile_result_required :: {:ok, PlanTypes.reg() | :fn_out, Builder.t()} | :unsupported
  @type compile_reg_result :: {:ok, PlanTypes.reg(), Builder.t()} | :unsupported
  @type match_condition_result :: {:ok, non_neg_integer(), Builder.t()} | :unsupported
end
