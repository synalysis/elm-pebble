defmodule Elmx.Pebble.Contract.TemplateCmdSubScan do
  @moduledoc false

  alias Elmx.Pebble.Contract.CmdSub

  @templates_root Path.expand("../../../../../ide/priv/project_templates", __DIR__)

  @type usage :: %{
          required(:template) => String.t(),
          required(:cmd_ids) => [atom()],
          required(:sub_ids) => [atom()],
          required(:targets) => [String.t()]
        }

  @spec templates_root() :: String.t()
  def templates_root, do: @templates_root

  @spec template_names() :: [String.t()]
  def template_names do
    @templates_root
    |> File.ls!()
    |> Enum.filter(fn name -> File.dir?(Path.join(@templates_root, name)) end)
    |> Enum.sort()
  end

  @spec usage(String.t()) :: usage()
  def usage(template) when is_binary(template) do
    targets = used_targets(template)
    target_set = MapSet.new(targets)

    cmd_ids =
      CmdSub.cmds()
      |> Enum.filter(fn row -> Enum.any?(row.elm_targets, &MapSet.member?(target_set, &1)) end)
      |> Enum.map(& &1.id)
      |> Enum.reject(&(&1 == :none))
      |> Enum.uniq()
      |> Enum.sort()

    sub_ids =
      CmdSub.subs()
      |> Enum.filter(fn row -> Enum.any?(row.elm_targets, &MapSet.member?(target_set, &1)) end)
      |> Enum.map(& &1.id)
      |> Enum.uniq()
      |> Enum.sort()

    %{template: template, cmd_ids: cmd_ids, sub_ids: sub_ids, targets: Enum.sort(targets)}
  end

  @spec used_targets(String.t()) :: [String.t()]
  def used_targets(template) when is_binary(template) do
    contract_targets = contract_target_set()

    template
    |> elm_sources()
    |> Enum.flat_map(fn source ->
      aliases = import_aliases(source)

      Enum.filter(contract_targets, fn target ->
        target_referenced?(source, aliases, target)
      end)
    end)
    |> Enum.uniq()
  end

  defp elm_sources(template) do
    root = Path.join(@templates_root, template)

    root
    |> Path.join("**/*.elm")
    |> Path.wildcard()
    |> Enum.map(&File.read!/1)
  end

  defp contract_target_set do
    (Enum.flat_map(CmdSub.cmds(), & &1.elm_targets) ++ Enum.flat_map(CmdSub.subs(), & &1.elm_targets))
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp import_aliases(source) do
    Regex.scan(~r/import\s+([A-Za-z0-9_.]+)(?:\s+as\s+([A-Za-z0-9_]+))?/, source)
    |> Map.new(fn
      [_, mod, alias] -> {alias, mod}
      [_, mod] -> {List.last(String.split(mod, ".")), mod}
    end)
  end

  defp target_referenced?(source, aliases, target) do
    leaf = target |> String.split(".") |> List.last()
    mod = target |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")

    qualified? = Regex.match?(~r/(?<![A-Za-z0-9_.])#{Regex.escape(target)}(?![A-Za-z0-9_])/, source)

    aliased? =
      Enum.any?(aliases, fn {alias, full} ->
        full == mod and
          Regex.match?(
            ~r/(?<![A-Za-z0-9_.])#{Regex.escape(alias <> "." <> leaf)}(?![A-Za-z0-9_])/,
            source
          )
      end)

    qualified? or aliased?
  end
end
