defmodule ElmEx.IR.Types.Lookup do
  @moduledoc """
  Name-resolution context threaded through `ElmEx.IR.Lowerer` rewrites.

  `rewrite_t/0` is the full per-module lookup built during lowering.
  `constructor_t/0` and `payload_kind_t/0` are narrower maps used in
  constructor arity diagnostics.
  """

  alias ElmEx.IR.ImportResolution

  @type tag_map :: %{String.t() => integer()}
  @type arity_map :: %{String.t() => non_neg_integer()}
  @type kind_map :: %{String.t() => atom()}

  @type constructor_t :: %{
          required(:local) => tag_map(),
          required(:unqualified) => tag_map(),
          required(:qualified) => tag_map(),
          optional(:alias_map) => %{String.t() => String.t()}
        }

  @type payload_kind_t :: %{
          required(:local) => kind_map(),
          required(:unqualified) => kind_map(),
          required(:qualified) => kind_map(),
          optional(:alias_map) => %{String.t() => String.t()}
        }

  @type rewrite_t :: %{
          optional(:local) => tag_map(),
          optional(:unqualified) => tag_map(),
          optional(:qualified) => tag_map(),
          optional(:payload_arity_local) => arity_map(),
          optional(:payload_arity_unqualified) => arity_map(),
          optional(:payload_arity_qualified) => arity_map(),
          optional(:current_module) => String.t(),
          optional(:alias_map) => %{String.t() => String.t()},
          optional(:import_unqualified_map) => map(),
          optional(:type_unqualified_map) => map(),
          optional(:wildcard_import_modules) => [String.t()] | list(),
          optional(:local_call_names) => MapSet.t(String.t()),
          optional(:let_bound_names) => MapSet.t(String.t())
        }

  @type t :: rewrite_t() | constructor_t() | payload_kind_t() | ImportResolution.lookup()
end
