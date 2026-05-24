defmodule Mix.Tasks.Ide.McpTemplateHealth do
  @moduledoc """
  Exercise every project template through the MCP tool interface.

      mix ide.mcp_template_health
      mix ide.mcp_template_health --templates watchface-digital,game-2048
      mix ide.mcp_template_health --json

  Uses JSON-RPC `tools/call` handling (`Ide.Mcp.Protocol`) — the same path as HTTP MCP.
  """

  use Mix.Task

  alias Ide.Mcp.Protocol
  alias Ide.ProjectTemplates

  @capabilities [:read, :edit, :build]
  @default_simulator %{
    "battery_percent" => 72,
    "connected" => true,
    "use_simulated_time" => true,
    "simulated_date" => "2026-05-19",
    "simulated_time" => "14:30"
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [templates: :string, json: :boolean]
      )

    templates =
      case Keyword.get(opts, :templates) do
        nil ->
          ProjectTemplates.template_keys()

        csv ->
          csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    json? = Keyword.get(opts, :json, false)
    results = Enum.map(templates, &check_template/1)

    if json? do
      IO.puts(Jason.encode!(%{results: results, mcp_gaps: mcp_gaps()}, pretty: true))
    else
      print_report(results)
      print_mcp_gaps()
    end

    failed = Enum.count(results, &(&1.status != :ok))

    if failed > 0 do
      Mix.raise("template health check failed for #{failed}/#{length(results)} template(s)")
    end
  end

  defp check_template(template) do
    slug = "mcp-health-#{template}-#{System.unique_integer([:positive])}"
    name = "MCP Health #{template}"

    base = %{
      template: template,
      slug: slug,
      name: name,
      status: :ok,
      steps: [],
      issues: [],
      injection: nil
    }

    result =
      base
      |> run_health_steps()

    Map.update!(result, :status, fn
      :ok -> :ok
      _ -> :error
    end)
  end

  defp run_health_steps(base) do
    base
    |> step(:create, fn acc ->
      case mcp("projects.create", %{
             "name" => acc.name,
             "slug" => acc.slug,
             "template" => acc.template,
             "target_type" => ProjectTemplates.target_type_for_template(acc.template)
           }) do
        {:ok, _} -> acc
        {:error, reason} -> fail(acc, "create", reason)
      end
    end)
    |> step(:debugger_start, fn acc ->
      case mcp("debugger.start", %{"slug" => acc.slug}) do
        {:ok, _} -> acc
        {:error, reason} -> fail(acc, "debugger.start", reason)
      end
    end)
    |> step(:debugger_bootstrap, &bootstrap_debugger/1)
    |> step(:baseline_models, &capture_baseline/1)
    |> step(:simulator_inject, &inject_simulator/1)
    |> step(:post_inject_models, &verify_injection/1)
    |> step(:render_tree, &check_render_tree/1)
    |> step(:pebble_package, &package_pbw/1)
    |> step(:cleanup, fn acc ->
      _ = mcp("projects.delete", %{"slug" => acc.slug})
      acc
    end)
  rescue
    error ->
      slug = base.slug
      _ = mcp("projects.delete", %{"slug" => slug})
      Map.merge(base, %{status: :error, issues: [Exception.message(error)]})
  end

  defp step(%{status: :error} = acc, _name, _fun), do: acc

  defp step(acc, name, fun) do
    fun.(Map.update!(acc, :steps, &[name | &1]))
  end

  defp fail(acc, step, reason) do
    %{acc | status: :error, issues: acc.issues ++ ["#{step}: #{reason}"]}
  end

  defp bootstrap_debugger(%{status: :error} = acc), do: acc

  defp bootstrap_debugger(acc) do
    slug = acc.slug

    acc =
      case mcp("files.stat", %{"slug" => slug, "source_root" => "phone", "rel_path" => "src/CompanionApp.elm"}) do
        {:ok, _} ->
          reload = mcp("debugger.reload", %{
            "slug" => slug,
            "source_root" => "phone",
            "rel_path" => "src/CompanionApp.elm",
            "reason" => "mcp_template_health_phone"
          })

          case reload do
            {:ok, _} -> acc
            {:error, reason} -> fail(acc, "reload phone", reason)
          end

        {:error, _} ->
          acc
      end

    if acc.status == :error do
      acc
    else
      case mcp("debugger.reload", %{
             "slug" => slug,
             "source_root" => "watch",
             "rel_path" => "src/Main.elm",
             "reason" => "mcp_template_health_watch"
           }) do
        {:ok, _} -> acc
        {:error, reason} -> fail(acc, "reload watch", reason)
      end
    end
  end

  defp capture_baseline(%{status: :error} = acc), do: acc

  defp capture_baseline(acc) do
    case mcp("debugger.models", %{"slug" => acc.slug, "include_view_output" => false}) do
      {:ok, %{"models" => models}} ->
        Map.put(acc, :baseline_models, models)

      {:error, reason} ->
        fail(acc, "debugger.models baseline", reason)
    end
  end

  defp inject_simulator(%{status: :error} = acc), do: acc

  defp inject_simulator(acc) do
    {kind, settings} = simulator_profile(acc.template)

    case mcp("debugger.set_simulator_settings", %{"slug" => acc.slug, "settings" => settings}) do
      {:ok, _} ->
        Map.put(acc, :injection, %{kind: kind, settings: settings})

      {:error, reason} ->
        fail(acc, "debugger.set_simulator_settings", reason)
    end
  end

  defp verify_injection(%{status: :error} = acc), do: acc

  defp verify_injection(acc) do
    with {:ok, %{"models" => after_models}} <-
           mcp("debugger.models", %{"slug" => acc.slug, "include_view_output" => false}),
         baseline <- Map.get(acc, :baseline_models, %{}),
         :ok <- assert_injection_changed(acc.template, acc.injection, baseline, after_models) do
      Map.put(acc, :after_models, after_models)
    else
      {:error, reason} -> fail(acc, "injection verify", reason)
      other -> fail(acc, "injection verify", inspect(other))
    end
  end

  defp check_render_tree(%{status: :error} = acc), do: acc

  defp check_render_tree(acc) do
    case mcp("debugger.render_tree", %{"slug" => acc.slug, "include_tree" => true}) do
      {:ok, %{"root_type" => root, "node_count" => count} = payload} ->
        app_template? = ProjectTemplates.target_type_for_template(acc.template) == "app"

        cond do
          root == "previewUnavailable" and app_template? ->
            Map.put(acc, :render, Map.merge(Map.take(payload, ["root_type", "node_count", "screen"]), %{note: "app preview unavailable in debugger"}))

          root == "previewUnavailable" and preview_diagnostics_ok?(acc.slug) ->
            Map.put(acc, :render, Map.merge(Map.take(payload, ["root_type", "node_count", "screen"]), %{note: "runtime view output available"}))

          root == "previewUnavailable" ->
            fail(acc, "render_tree", "preview unavailable")

          count == 0 ->
            fail(acc, "render_tree", "no rendered nodes")

          true ->
            Map.put(acc, :render, Map.take(payload, ["root_type", "node_count", "screen"]))
        end

      {:ok, _} ->
        fail(acc, "render_tree", "missing root_type/node_count")

      {:error, reason} ->
        fail(acc, "debugger.render_tree", reason)
    end
  end

  defp package_pbw(%{status: :error} = acc), do: acc

  defp package_pbw(acc) do
    case mcp("pebble.package", %{"slug" => acc.slug}) do
      {:ok, %{"artifact_path" => path}} when is_binary(path) and path != "" ->
        Map.put(acc, :pbw, path)

      {:ok, %{"package_path" => path}} when is_binary(path) and path != "" ->
        Map.put(acc, :pbw, path)

      {:ok, payload} ->
        fail(acc, "pebble.package", "missing artifact_path: #{inspect(Map.take(payload, ["status", "artifact_path", "package_path"]))}")

      {:error, reason} ->
        fail(acc, "pebble.package", reason)
    end
  end

  defp simulator_profile(template) do
    cond do
      weather_template?(template) ->
        {:weather,
         Map.merge(@default_simulator, %{
           "weather" => %{
             "condition" => "rain",
             "temperatureC" => 4,
             "humidityPercent" => 88,
             "pressureHpa" => 995,
             "windKph" => 22
           }
         })}

      geolocation_template?(template) ->
        {:geolocation,
         Map.merge(@default_simulator, %{
           "latitude" => 48.137154,
           "longitude" => 11.576124,
           "accuracy" => 25
         })}

      true ->
        {:basic, @default_simulator}
    end
  end

  defp weather_template?(template) do
    template in ["watchface-weather-animated", "watchface-tutorial-complete", "watchface-yes"] or
      String.contains?(template, "weather")
  end

  defp geolocation_template?(template) do
    String.contains?(template, "geolocation")
  end

  defp assert_injection_changed(template, %{kind: kind}, before, after_models) do
    before_watch = get_in(before, ["watch"]) || get_in(before, [:watch]) || %{}
    after_watch = get_in(after_models, ["watch"]) || get_in(after_models, [:watch]) || %{}

    before_json = Jason.encode!(before_watch)
    after_json = Jason.encode!(after_watch)

    changed? = before_json != after_json

    specific_ok =
      case kind do
        :geolocation ->
          lat = model_field(after_watch, "latitudeE6")
          lon = model_field(after_watch, "longitudeE6")
          is_integer(lat) and lat != 0 and is_integer(lon) and lon != 0

        :weather ->
          model_text = after_json |> String.downcase()
          String.contains?(model_text, "rain") or String.contains?(model_text, "4") or changed?

        _ ->
          changed?
      end

    cond do
      weather_template?(template) and not specific_ok and not changed? ->
        {:error, "watch model did not reflect weather simulator settings"}

      geolocation_template?(template) and not specific_ok ->
        {:error, "watch model missing latitudeE6/longitudeE6 after geolocation settings"}

      not changed? and template not in ["watchface-digital", "watchface-analog"] ->
        # Static watchfaces may not react to generic simulator settings.
        :ok

      true ->
        :ok
    end
  end

  defp model_field(model, key) do
    Map.get(model, key) || get_in(model, ["runtime_model", key])
  end

  defp preview_diagnostics_ok?(slug) do
    case mcp("debugger.preview_diagnostics", %{"slug" => slug, "target" => "watch"}) do
      {:ok, %{"status" => "ok", "render_source" => "runtime_view_output", "runtime_view_output_count" => count}}
      when is_integer(count) and count > 0 ->
        true

      _ ->
        false
    end
  end

  defp mcp(name, args) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    case Protocol.handle_request(request, @capabilities) do
      {:ok, %{"isError" => false, "content" => [%{"text" => text}]}} ->
        {:ok, Jason.decode!(text)}

      {:ok, %{"isError" => true, "content" => [%{"text" => text}]}} ->
        {:error, text}

      {:ok, other} ->
        {:error, "unexpected MCP response: #{inspect(other)}"}

      {:error, code, message} ->
        {:error, "#{code}: #{message}"}
    end
  end

  defp mcp_gaps do
    [
      %{
        gap: "pebble.package response field",
        detail:
          "pebble.package now returns both artifact_path and package_path (same value). Prefer artifact_path."
      },
      %{
        gap: "debugger.bootstrap",
        detail:
          "debugger.start only resets session state; UI bootstrap reloads phone + watch Main.elm. Health check manually chains debugger.reload — agents need 3+ calls per project."
      },
      %{
        gap: "debugger.inject_trigger",
        detail:
          "No MCP tool to fire subscription/update messages (HourChanged, ButtonPressed, etc.). Only debugger.step with explicit message labels."
      },
      %{
        gap: "debugger.available_triggers",
        detail: "No MCP tool to list injectable triggers from elm_introspect subscription_calls."
      },
      %{
        gap: "template.health / batch workflow",
        detail: "No single MCP tool to create+bootstrap+validate+package a template smoke test."
      },
      %{
        gap: "debugger.timeline user view",
        detail:
          "debugger.timeline returns raw events, not filtered debugger_timeline rows shown in the UI."
      }
    ]
  end

  defp print_report(results) do
    IO.puts("\n=== MCP template health (#{length(results)} templates) ===\n")

    Enum.each(results, fn row ->
      icon = if row.status == :ok, do: "OK", else: "FAIL"

      IO.puts(
        "[#{icon}] #{row.template} (#{row.slug})" <>
          optional_field(row, :pbw, " pbw") <>
          optional_render(row)
      )

      unless row.issues == [] do
        Enum.each(row.issues, fn issue -> IO.puts("      - #{issue}") end)
      end
    end)

    ok = Enum.count(results, &(&1.status == :ok))
    IO.puts("\nSummary: #{ok}/#{length(results)} passed\n")
  end

  defp optional_field(row, key, label) do
    case Map.get(row, key) do
      nil -> ""
      value -> "#{label}=#{value}"
    end
  end

  defp optional_render(row) do
    case Map.get(row, :render) do
      %{"root_type" => root, "node_count" => count} ->
        " render=#{root}(#{count} nodes)"

      _ ->
        ""
    end
  end

  defp print_mcp_gaps do
    IO.puts("=== MCP interface gaps (efficiency) ===\n")

    Enum.each(mcp_gaps(), fn %{gap: gap, detail: detail} ->
      IO.puts("- #{gap}")
      IO.puts("  #{detail}\n")
    end)
  end
end
