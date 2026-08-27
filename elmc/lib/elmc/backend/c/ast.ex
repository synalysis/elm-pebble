defmodule Elmc.Backend.C.Ast do
  @moduledoc """
  Typed C fragments for RC function shells.

  Instruction bodies still come from `C.Lower.Instr` as text. The function
  shell (owned slots, CATCH, LIFO epilogue, single `return Rc`) is an AST so
  lint can prove the RC ABI shape before pretty-print.
  """

  defmodule RcFn do
    @moduledoc false

    @type stmt ::
            {:decl_rc}
            | {:decl_owned, String.t()}
            | {:letrec, String.t()}
            | {:catch_begin}
            | {:raw, String.t()}
            | {:catch_end}
            | {:epilogue, String.t()}
            | {:return_rc}

    defstruct [
      :rc?,
      :owned_count,
      :needs_catch,
      :stmts
    ]

    @type t :: %__MODULE__{
            rc?: boolean(),
            owned_count: non_neg_integer(),
            needs_catch: boolean(),
            stmts: [stmt()]
          }
  end

  @spec rc_fn(keyword()) :: RcFn.t()
  def rc_fn(opts) do
    rc? = Keyword.get(opts, :rc?, true)
    owned_decl = Keyword.get(opts, :owned_decl, "")
    owned_count = Keyword.get(opts, :owned_count, 0)
    needs_catch? = Keyword.get(opts, :needs_catch, false)
    body = Keyword.get(opts, :body, "")
    letrec_decls = Keyword.get(opts, :letrec_decls, [])
    letrec_free = Keyword.get(opts, :letrec_free, [])
    epilogue = Keyword.get(opts, :epilogue, "")

    stmts =
      Enum.reject(
        List.wrap(if(rc?, do: {:decl_rc})) ++
          Enum.map(letrec_decls, &{:letrec, &1}) ++
          List.wrap(if(owned_decl != "", do: {:decl_owned, owned_decl})) ++
          List.wrap(if(needs_catch?, do: {:catch_begin})) ++
          [{:raw, body}] ++
          List.wrap(if(needs_catch?, do: {:catch_end})) ++
          Enum.map(letrec_free, &{:letrec, &1}) ++
          List.wrap(if(epilogue != "", do: {:epilogue, epilogue})) ++
          List.wrap(if(rc?, do: {:return_rc})),
        fn
          nil -> true
          {:raw, ""} -> true
          {:letrec, ""} -> true
          {:epilogue, ""} -> true
          {:decl_owned, ""} -> true
          _ -> false
        end
      )

    %RcFn{
      rc?: rc?,
      owned_count: owned_count,
      needs_catch: needs_catch?,
      stmts: stmts
    }
  end
end
