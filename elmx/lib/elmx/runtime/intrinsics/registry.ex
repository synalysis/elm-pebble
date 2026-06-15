defmodule Elmx.Runtime.Intrinsics.Registry do
  @moduledoc """
  Handler table for `elmc_*` runtime intrinsics emitted by the C/Flint backend.

  Used by `Elmx.Runtime.Intrinsics` and `Elmx.Runtime.Generator` (before the Pebble registry).
  Compile/invoke paths go through `Elmx.Runtime.Handler` and `CodegenRefs`.
  """

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Intrinsics.Registry.{
    Basics,
    Bitwise,
    Char,
    Collections,
    ElmxCore,
    Json,
    List,
    MaybeResult,
    Platform,
    Singleton,
    Strings,
    Tuple
  }

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{}
    |> Map.merge(ElmxCore.handlers())
    |> Map.merge(Singleton.handlers())
    |> Map.merge(Collections.handlers())
    |> Map.merge(List.handlers())
    |> Map.merge(Strings.handlers())
    |> Map.merge(Basics.handlers())
    |> Map.merge(Bitwise.handlers())
    |> Map.merge(Char.handlers())
    |> Map.merge(MaybeResult.handlers())
    |> Map.merge(Json.handlers())
    |> Map.merge(Tuple.handlers())
    |> Map.merge(Platform.handlers())
  end
end
