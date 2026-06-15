defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.Context do
  @moduledoc false

  alias Elmx.Types

  @type env :: Types.emit_env()
  @type emit_counter :: Types.emit_counter()
  @type ir_arg_list :: Types.ir_arg_list()
  @type compile_expr_result :: Types.compile_expr_result()

  @type qualified_result :: {:ok, iodata(), env(), emit_counter()} | :error
  @type qualified_string_result :: {:ok, String.t(), env(), emit_counter()} | :error
end
