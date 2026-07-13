defmodule ElmEx.IR.Types.FieldValue do
  @moduledoc false

  @type literal :: integer() | float() | boolean() | String.t() | atom() | nil

  @type tuple2 :: {t(), t()}

  @type t ::
          ElmEx.IR.Types.Expr.t()
          | literal()
          | [t()]
          | tuple2()
end
