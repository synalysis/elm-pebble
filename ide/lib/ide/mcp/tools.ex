defmodule Ide.Mcp.Tools do
  @moduledoc """
  Capability-scoped MCP tool registry and dispatcher for IDE operations.
  """

  alias Ide.Mcp.{VectorResources}
  alias Ide.Mcp.ToolCatalog
  alias Ide.Mcp.Handlers.Build, as: BuildHandler
  alias Ide.Mcp.Handlers.Compiler, as: CompilerHandler
  alias Ide.Mcp.Handlers.Debugger, as: DebuggerHandler
  alias Ide.Mcp.Handlers.Emulator, as: EmulatorHandler
  alias Ide.Mcp.Handlers.Packages, as: PackagesHandler
  alias Ide.Mcp.Handlers.Projects, as: ProjectsHandler
  alias Ide.Mcp.Handlers.Traces, as: TracesHandler
  alias Ide.Mcp.ToolTypes

  @type capability :: :read | :edit | :build | :publish
  @type tool_result :: ToolTypes.tool_result()

  @spec tool_definitions([capability()]) :: [ToolCatalog.tool_definition()]
  def tool_definitions(capabilities), do: ToolCatalog.tool_definitions(capabilities)

  @spec catalog_version() :: String.t()
  def catalog_version, do: ToolCatalog.catalog_version()

  @spec call(String.t(), ToolTypes.tool_args(), [capability()]) :: tool_result()
  def call(name, args, capabilities) when is_binary(name) and is_map(args) do
    internal_name = ToolCatalog.internal_tool_name(name)

    if ToolCatalog.authorized?(internal_name, capabilities) do
      do_call(internal_name, args)
    else
      {:error, "tool not permitted by current capability scope"}
    end
  end

  @spec audit_arguments(String.t(), ToolTypes.tool_args()) :: ToolTypes.tool_audit_args()
  def audit_arguments(name, args) when is_binary(name) and is_map(args) do
    name
    |> ToolCatalog.internal_tool_name()
    |> do_audit_arguments(args)
  end

  @spec do_audit_arguments(String.t(), ToolTypes.tool_args()) :: ToolTypes.tool_audit_args()
  defp do_audit_arguments("files.write", %{"content" => content} = args)
       when is_binary(content) do
    args
    |> Map.drop(["content"])
    |> Map.put("content_redacted", true)
    |> Map.put("content_bytes", byte_size(content))
  end

  defp do_audit_arguments("files.patch", args) do
    args
    |> redact_patch_argument("old_string")
    |> redact_patch_argument("new_string")
  end

  defp do_audit_arguments("debugger.import_trace", %{"export_json" => json} = args)
       when is_binary(json) do
    args
    |> Map.drop(["export_json"])
    |> Map.put("export_json_redacted", true)
    |> Map.put("export_json_bytes", byte_size(json))
  end

  defp do_audit_arguments("debugger.reload", %{"source" => source} = args)
       when is_binary(source) do
    args
    |> Map.drop(["source"])
    |> Map.put("source_redacted", true)
    |> Map.put("source_bytes", byte_size(source))
  end

  defp do_audit_arguments("resources.vectors.convert", %{"svg" => svg} = args)
       when is_binary(svg) do
    args
    |> Map.drop(["svg"])
    |> Map.put("svg_redacted", true)
    |> Map.put("svg_bytes", byte_size(svg))
  end

  defp do_audit_arguments("resources.vectors.import", %{"svg" => svg} = args)
       when is_binary(svg) do
    args
    |> Map.drop(["svg"])
    |> Map.put("svg_redacted", true)
    |> Map.put("svg_bytes", byte_size(svg))
  end

  defp do_audit_arguments("resources.vectors.convert_sequence", %{"frames" => frames} = args)
       when is_list(frames) do
    args
    |> Map.put("frame_count", length(frames))
    |> Map.put("frames_redacted", true)
  end

  defp do_audit_arguments("resources.vectors.import_sequence", %{"frames" => frames} = args)
       when is_list(frames) do
    args
    |> Map.put("frame_count", length(frames))
    |> Map.put("frames_redacted", true)
  end

  defp do_audit_arguments("resources.vectors.preview", %{"bytes_base64" => _} = args) do
    Map.put(args, "bytes_base64_redacted", true)
  end

  defp do_audit_arguments(_name, args) when is_map(args), do: args

  @spec do_call(String.t(), ToolTypes.tool_args()) :: tool_result()
  defp do_call("templates." <> _rest = name, args), do: ProjectsHandler.call(name, args)
  defp do_call("projects." <> _rest = name, args), do: ProjectsHandler.call(name, args)
  defp do_call("files." <> _rest = name, args), do: ProjectsHandler.call(name, args)
  defp do_call("packages." <> _rest = name, args), do: PackagesHandler.call(name, args)
  defp do_call("pebble." <> _rest = name, args), do: BuildHandler.call(name, args)
  defp do_call("emulator." <> _rest = name, args), do: EmulatorHandler.call(name, args)
  defp do_call("screenshots." <> _rest = name, args), do: BuildHandler.call(name, args)
  defp do_call("audit.recent", args), do: CompilerHandler.call("audit.recent", args)
  defp do_call("compiler." <> _rest = name, args), do: CompilerHandler.call(name, args)
  defp do_call("publish." <> _rest = name, args), do: CompilerHandler.call(name, args)
  defp do_call("traces." <> _rest = name, args), do: TracesHandler.call(name, args)
  defp do_call("sessions." <> _rest = name, args), do: TracesHandler.call(name, args)
  defp do_call("debugger." <> _rest = name, args), do: DebuggerHandler.call(name, args)
  defp do_call("resources.vectors.list", %{"slug" => slug}), do: VectorResources.list(slug)
  defp do_call("resources.vectors.convert", args), do: VectorResources.convert(args)

  defp do_call("resources.vectors.convert_sequence", args),
    do: VectorResources.convert_sequence(args)

  defp do_call("resources.vectors.import", args), do: VectorResources.import(args)

  defp do_call("resources.vectors.import_sequence", args),
    do: VectorResources.import_sequence(args)

  defp do_call("resources.vectors.preview", args), do: VectorResources.preview(args)
  defp do_call("resources.vectors.delete", args), do: VectorResources.delete(args)
  defp do_call(name, _args), do: {:error, "unknown tool: #{name}"}

  @spec redact_patch_argument(ToolTypes.tool_audit_args(), String.t()) :: ToolTypes.tool_audit_args()
  defp redact_patch_argument(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        args
        |> Map.delete(key)
        |> Map.put("#{key}_redacted", true)
        |> Map.put("#{key}_bytes", byte_size(value))

      _other ->
        args
    end
  end
end
