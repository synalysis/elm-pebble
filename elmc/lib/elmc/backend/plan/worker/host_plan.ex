defmodule Elmc.Backend.Plan.Worker.HostPlan do
  @moduledoc """
  Plan-owned IR for the Elm worker TEA host shell (`elmc_worker_init` / `dispatch`).

  App `init` / `update` / `subscriptions` bodies are `FunctionPlan` SSA; this struct
  describes the host adapter that calls them and manages `ElmcWorkerState`.
  """
  alias Elmc.Backend.Plan.Worker.Layout

  @type entry_abi :: :direct | :argc
  @type fail_kind :: :init_fail | :update_fail | :sub_fail | :generic_fail

  @type entry_call :: %{
          required(:safe_module) => String.t(),
          required(:fun) => String.t(),
          required(:abi) => entry_abi(),
          required(:arg_exprs) => [String.t()],
          required(:rc_var) => String.t(),
          required(:fail_kind) => fail_kind(),
          optional(:on_fail_c) => String.t(),
          optional(:call_c) => String.t()
        }

  @type entry :: %{
          required(:present?) => boolean(),
          optional(:call) => entry_call(),
          optional(:missing_return) => integer(),
          optional(:stub_c) => String.t()
        }

  @type t :: %__MODULE__{
          entry_module: String.t(),
          layout: Layout.t(),
          init: entry(),
          update: entry(),
          subscriptions: entry(),
          model_dependent_subs?: boolean(),
          last_dispatch_cmd_cap: non_neg_integer()
        }

  defstruct [
    :entry_module,
    :layout,
    :init,
    :update,
    :subscriptions,
    model_dependent_subs?: false,
    last_dispatch_cmd_cap: 8
  ]
end
