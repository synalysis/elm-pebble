defmodule Elmc.Runtime.Generator.Types do
  @moduledoc """
  Shared types for runtime C source generation and pruning.
  """

  @type runtime_source :: String.t()
  @type runtime_header :: String.t()
  @type runtime_ref_map :: %{String.t() => true}
  @type function_def :: %{
          name: String.t(),
          start_idx: non_neg_integer(),
          end_idx: non_neg_integer(),
          body: runtime_source()
        }
  @type def_map :: %{String.t() => runtime_source()}
  @type keep_set :: MapSet.t(String.t())
  @type line_offsets :: [non_neg_integer()]
  @type brace_result :: {:ok, non_neg_integer()} | {:error, :unbalanced_braces}
  @type prune_pair :: {runtime_header(), runtime_source()}
  @type file_error :: File.posix()
end
