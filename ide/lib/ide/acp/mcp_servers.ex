defmodule Ide.Acp.McpServers do
  @moduledoc """
  MCP server configurations that the IDE can pass to ACP agents.

  ACP sessions accept MCP server declarations so the agent can connect back to
  IDE-provided tools. This module keeps that configuration independent from the
  ACP transport client.
  """

  @valid_capabilities ~w(read edit build)

  @doc """
  Returns a stdio MCP server declaration for the IDE's own MCP server.
  """
  @spec ide_stdio(keyword()) :: map()
  def ide_stdio(opts \\ []) do
    capabilities =
      opts
      |> Keyword.get(:capabilities, [:read])
      |> normalize_capabilities()

    ide_dir = Keyword.get(opts, :ide_dir, configured_ide_dir())

    command =
      Keyword.get_lazy(opts, :command, fn -> System.find_executable("bash") || "/usr/bin/bash" end)

    %{
      "name" => Keyword.get(opts, :name, "elm-pebble-ide"),
      "command" => command,
      "args" => [
        "-lc",
        "cd #{shell_quote(ide_dir)} && exec mix ide.mcp --capabilities #{shell_quote(capabilities)}"
      ],
      "env" => env_variables(Keyword.get(opts, :env, []))
    }
  end

  defp normalize_capabilities(capabilities) when is_binary(capabilities) do
    capabilities
    |> String.split(",", trim: true)
    |> normalize_capabilities()
  end

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(&1 in @valid_capabilities))
    |> case do
      [] -> ["read"]
      list -> Enum.uniq(list)
    end
    |> Enum.join(",")
  end

  defp normalize_capabilities(_capabilities), do: "read"

  defp env_variables(env) when is_map(env) do
    Enum.map(env, fn {name, value} ->
      %{"name" => to_string(name), "value" => to_string(value)}
    end)
  end

  defp env_variables(env) when is_list(env) do
    Enum.map(env, fn
      {name, value} ->
        %{"name" => to_string(name), "value" => to_string(value)}

      %{"name" => name, "value" => value} ->
        %{"name" => to_string(name), "value" => to_string(value)}

      %{name: name, value: value} ->
        %{"name" => to_string(name), "value" => to_string(value)}
    end)
  end

  defp env_variables(_env), do: []

  defp configured_ide_dir do
    :ide
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ide_dir, default_ide_dir())
    |> Path.expand()
  end

  defp default_ide_dir do
    cwd = File.cwd!()

    cond do
      Path.basename(cwd) == "ide" and File.exists?(Path.join(cwd, "mix.exs")) ->
        cwd

      File.exists?(Path.join([cwd, "ide", "mix.exs"])) ->
        Path.join(cwd, "ide")

      true ->
        cwd
    end
  end

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end
end
