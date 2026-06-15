defmodule Elmx.Runtime.CodegenRefs do
  @moduledoc """
  Stable module paths emitted by `Stdlib`, `Emit`, and `Handler` registry codegen.

  String codegen (`Stdlib.Qualified`), IR emit (`Emit.Qualified`), and registry
  `Handler.compile/3` all resolve runtime modules through this module so renames stay
  centralized. Use `module_ref/1` when lowering a registry handler module atom.

  ## Qualified call pipeline

  * **IR emit** (`Emit.Qualified`): rewrites → Pebble/UI/list/string/collections rules →
    fallback (`try_stdlib_qualified_ir` → Basics/Bitwise → `Stdlib.qualified_call/2`).
  * **String codegen** (`Stdlib.Qualified`): `special_call` then `Stdlib.Qualified.call/2`,
    sharing fragments via `Stdlib.QualifiedCodegen`.
  * **Registry** (`Handler.compile/3`): `elmc_*` / `elmx_*` intrinsics (this module’s paths).
  """

  @spec maybe_result() :: String.t()
  def maybe_result, do: "Elmx.Runtime.Core.MaybeResult"

  @spec core() :: String.t()
  def core, do: "Elmx.Runtime.Core"

  @spec core_list() :: String.t()
  def core_list, do: "Elmx.Runtime.Core.List"

  @spec core_collections() :: String.t()
  def core_collections, do: "Elmx.Runtime.Core.Collections"

  @spec json_encode() :: String.t()
  def json_encode, do: "Elmx.Runtime.Json.Encode"

  @spec json_decode() :: String.t()
  def json_decode, do: "Elmx.Runtime.Json.Decode"

  @spec core_strings() :: String.t()
  def core_strings, do: "Elmx.Runtime.Core.Strings"

  @spec core_task() :: String.t()
  def core_task, do: "Elmx.Runtime.Core.Task"

  @spec core_process() :: String.t()
  def core_process, do: "Elmx.Runtime.Core.Process"

  @spec core_apply() :: String.t()
  def core_apply, do: "Elmx.Runtime.Core.Apply"

  @spec pebble_ui() :: String.t()
  def pebble_ui, do: "Elmx.Runtime.Pebble.Ui"

  @spec values() :: String.t()
  def values, do: "Elmx.Runtime.Values"

  @spec cmd() :: String.t()
  def cmd, do: "Elmx.Runtime.Cmd"

  @spec core_math() :: String.t()
  def core_math, do: "Elmx.Runtime.Core.Math"

  @spec core_chars() :: String.t()
  def core_chars, do: "Elmx.Runtime.Core.Chars"

  @spec core_bitwise() :: String.t()
  def core_bitwise, do: "Elmx.Runtime.Core.Bitwise"

  @spec pebble() :: String.t()
  def pebble, do: "Elmx.Runtime.Pebble"

  @spec core_debug() :: String.t()
  def core_debug, do: "Elmx.Runtime.Core.Debug"

  @spec core_time() :: String.t()
  def core_time, do: "Elmx.Runtime.Core.Time"

  @spec core_tuple() :: String.t()
  def core_tuple, do: "Elmx.Runtime.Core.Tuple"

  @spec http() :: String.t()
  def http, do: "Elmx.Runtime.Http"

  @spec pebble_dispatch() :: String.t()
  def pebble_dispatch, do: "Elmx.Runtime.Pebble.Dispatch"

  @module_ref_funs %{
    Elmx.Runtime.Core => :core,
    Elmx.Runtime.Core.List => :core_list,
    Elmx.Runtime.Core.Collections => :core_collections,
    Elmx.Runtime.Core.MaybeResult => :maybe_result,
    Elmx.Runtime.Core.Strings => :core_strings,
    Elmx.Runtime.Core.Task => :core_task,
    Elmx.Runtime.Core.Process => :core_process,
    Elmx.Runtime.Core.Apply => :core_apply,
    Elmx.Runtime.Core.Math => :core_math,
    Elmx.Runtime.Core.Chars => :core_chars,
    Elmx.Runtime.Core.Bitwise => :core_bitwise,
    Elmx.Runtime.Core.Debug => :core_debug,
    Elmx.Runtime.Core.Time => :core_time,
    Elmx.Runtime.Core.Tuple => :core_tuple,
    Elmx.Runtime.Json.Encode => :json_encode,
    Elmx.Runtime.Json.Decode => :json_decode,
    Elmx.Runtime.Pebble => :pebble,
    Elmx.Runtime.Pebble.Ui => :pebble_ui,
    Elmx.Runtime.Pebble.Dispatch => :pebble_dispatch,
    Elmx.Runtime.Http => :http,
    Elmx.Runtime.Values => :values,
    Elmx.Runtime.Cmd => :cmd
  }

  @spec module_ref(module()) :: String.t()
  def module_ref(mod) when is_atom(mod) do
    case Map.get(@module_ref_funs, mod) do
      nil -> mod |> Module.split() |> Enum.join(".")
      fun -> apply(__MODULE__, fun, [])
    end
  end

  @spec registry_modules() :: [module()]
  def registry_modules, do: Map.keys(@module_ref_funs)
end
