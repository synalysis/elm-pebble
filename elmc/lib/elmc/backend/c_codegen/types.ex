defmodule Elmc.Backend.CCodegen.Types do
  @moduledoc """
  Shared types for IR-to-C code generation.
  """

  @type ir_expr :: map()
  @type compile_env :: map()
  @type compile_counter :: non_neg_integer()
  @type compile_result :: {String.t(), String.t(), compile_counter()}
  @type compile_result_or_nil :: compile_result() | nil
  @type pattern :: map()
  @type subject_ref :: String.t() | ir_expr()
  @type codegen_opts :: map()
  @type file_error :: File.posix()
end
