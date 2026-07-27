defmodule Elmc.Backend.Wasm.WebCoverage do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Plan.PrimaryCoverage

  @server_only_prefixes [
    "Pages.StaticHttp.",
    "Pages.Internal.Platform.Cli",
    "Pages.Internal.Platform.GeneratorApplication"
  ]

  @server_only_backend_task_prefixes [
    "BackendTask.",
    "BackendTask"
  ]

  @server_only_exact MapSet.new([
    {"BackendTask.Http", "requestRawUnchecked"},
    {"BackendTask.Internal.Request", "requestWithHeaders"}
  ])

  @spec filter_reachable(CCodegenTypes.function_decl_map(), keyword() | map()) ::
          CCodegenTypes.function_decl_map()
  def filter_reachable(decl_map, opts) when is_map(decl_map) do
    decl_map
    |> PrimaryCoverage.filter_reachable(opts)
    |> drop_server_only()
  end

  @spec server_only?({String.t(), String.t()}) :: boolean()
  def server_only?({module, name}) when is_binary(module) and is_binary(name) do
    cond do
      MapSet.member?(@server_only_exact, {module, name}) ->
        true

      module == "BackendTask.Http" ->
        false

      server_only_backend_task?(module) ->
        true

      true ->
        Enum.any?(@server_only_prefixes, fn prefix ->
          module == prefix or String.starts_with?(module, prefix <> ".")
        end)
    end
  end

  @spec server_only_backend_task?(String.t()) :: boolean()

  defp server_only_backend_task?(module) when is_binary(module) do
    Enum.any?(@server_only_backend_task_prefixes, fn prefix ->
      module == prefix or String.starts_with?(module, prefix <> ".")
    end)
  end

  @spec drop_server_only(Types.decl_map()) :: Types.ir_expr()

  defp drop_server_only(decl_map) do
    decl_map
    |> Enum.reject(fn {key, _} -> server_only?(key) end)
    |> Map.new()
  end
end
