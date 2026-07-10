defmodule Elmc.Backend.Plan.Types do
  @moduledoc """
  Target-neutral SSA plan IR between Elm IR and backends (C, bytecode, WASM).

  Plans describe Elm value semantics and ownership — not C ABI details
  (`owned[]`, `CHECK_RC`, `CATCH_BEGIN`). Backends lower the same verified
  `%FunctionPlan{}` to their target representation.
  """

  @typedoc "SSA virtual register index."
  @type reg :: non_neg_integer()

  @typedoc "Function result slot (single per success path)."
  @type result_slot :: :fn_out | :branch_out

  @type owned :: {:owned, reg()}

  @type effects :: %{
          optional(:produces) => owned() | nil,
          optional(:consumes) => [reg()],
          optional(:borrows) => [reg()],
          required(:fallible) => boolean()
        }

  @type opcode ::
          :const_int
          | :const_c_expr
          | :const_static_list
          | :const_immortal_string
          | :load_param
          | :load_local
          | :call_runtime
          | :call_fn
          | :call_closure
          | :retain
          | :release
          | :transfer
          | :publish
          | :br
          | :br_if
          | :switch_tag
          | :ret
          | :catch_begin
          | :catch_end
          | :make_closure
          | :union_tag
          | :maybe_is_nothing
          | :switch_ctor_tag
          | :boxed_tag_peel
          | :test_maybe_nothing
          | :test_list_empty
          | :test_ctor_tag
          | :test_bool
          | :test_string_literal
          | :bool_and
          | :compare
          | :record_get
          | :record_get_int
          | :tuple_proj
          | :tuple2
          | :record_new
          | :record_update
          |       :list_literal
          | :phi
          | :int_arith
          | :boxed_binop
          | :pebble_cmd
          | :render_cmd
          | :render_text_cmd
          | :list_cursor_map
          | :pebble_sub
          | :forward_ref_set
          | :forward_ref_load
          | :forward_ref_capture
          | :forward_ref_load_captured

  defstruct [
    :id,
    :op,
    :dest,
    :args,
    :effects,
    :block_id,
    :span
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          op: opcode(),
          dest: reg() | result_slot() | nil,
          args: map(),
          effects: effects(),
          block_id: non_neg_integer(),
          span: term()
        }

  defmodule Block do
    @moduledoc false
    @type terminator ::
            {:br, non_neg_integer()}
            | {:br_if, non_neg_integer(), non_neg_integer(), Elmc.Backend.Plan.Types.reg()}
            | {:switch_tag, Elmc.Backend.Plan.Types.reg(), [
                {integer(), non_neg_integer()}
              ], non_neg_integer()}
            | {:ret, Elmc.Backend.Plan.Types.reg() | :fn_out}
            | :none

    defstruct [:id, :instrs, :terminator]

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            instrs: [Elmc.Backend.Plan.Types.t()],
            terminator: terminator()
          }
  end

  defmodule Param do
    @moduledoc false
    defstruct [:name, :type, :index]

    @type t :: %__MODULE__{
            name: String.t(),
            type: String.t() | nil,
            index: non_neg_integer()
          }
  end

  defmodule FunctionPlan do
    @moduledoc """
  A lowered function body as verified SSA plan.

  `params` and `fallible` are target-agnostic signature metadata shared by
  C, bytecode, and future WASM backends.
  """

    defstruct [
      :module,
      :name,
      :params,
      :return_type,
      :fallible,
      :rc_required,
      :blocks,
      :entry_block,
      :locals,
      :reg_count,
      :catch_depth,
      :lambdas,
      :lambda_arg_count,
      :letrec_refs,
      :fusion_c,
      :native_scalar_return,
      :native_scalar_value_return
    ]

    @type t :: %__MODULE__{
            module: String.t(),
            name: String.t(),
            params: [Elmc.Backend.Plan.Types.Param.t()],
            return_type: String.t() | nil,
            fallible: boolean(),
            rc_required: boolean(),
            blocks: [Elmc.Backend.Plan.Types.Block.t()],
            entry_block: non_neg_integer(),
            locals: %{String.t() => Elmc.Backend.Plan.Types.reg()},
            reg_count: non_neg_integer(),
            catch_depth: non_neg_integer(),
            lambdas: [FunctionPlan.t()],
            lambda_arg_count: non_neg_integer() | nil,
            letrec_refs: [String.t()],
            fusion_c: String.t() | nil,
            native_scalar_return: :native_int | :native_bool | nil,
            native_scalar_value_return: boolean()
          }
  end

  @type function_plan :: FunctionPlan.t()

  @spec empty_effects() :: effects()
  def empty_effects, do: %{produces: nil, consumes: [], borrows: [], fallible: false}

  @spec owned_effects(reg()) :: effects()
  def owned_effects(reg) when is_integer(reg),
    do: %{produces: {:owned, reg}, consumes: [], borrows: [], fallible: false}

  def owned_effects(_),
    do: %{produces: nil, consumes: [], borrows: [], fallible: false}

  @spec fallible_effects(reg() | result_slot(), [reg()], [reg()]) :: effects()
  def fallible_effects(reg, borrows \\ [], consumes \\ []) do
    produces = if is_integer(reg), do: {:owned, reg}, else: nil

    %{
      produces: produces,
      consumes: consumes,
      borrows: borrows,
      fallible: true
    }
  end

  @spec fallible_transfer([reg()], [reg()]) :: effects()
  def fallible_transfer(borrows, consumes) do
    %{
      produces: nil,
      consumes: consumes,
      borrows: borrows,
      fallible: true
    }
  end
end
