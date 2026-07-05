defmodule Ide.TemplateElmxElmcParityCaseTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ide.Test.TemplateElmxElmcParity, as: Parity

  @tag :template_parity_case
  @tag timeout: 300_000
  test "isolated template parity case from env" do
    template_key = System.fetch_env!("TEMPLATE_PARITY_TEMPLATE")

    on_exit(fn -> Parity.release!(template_key) end)

    assert {:ok, prepared} = Parity.prepare!(template_key)

    for watch_profile_id <- Parity.watch_profiles(), profile_filter?(watch_profile_id) do
      case Parity.compare!(template_key, watch_profile_id, prepared: prepared) do
        {:ok, _result} ->
          :ok

        {:mismatch, result} ->
          flunk(Parity.format_mismatch_report(result))

        {:error, reason} ->
          flunk("template parity error for #{template_key}/#{watch_profile_id}: #{inspect(reason)}")
      end
    end
  end

  defp profile_filter?(watch_profile_id) do
    case System.get_env("TEMPLATE_PARITY_PROFILE") do
      nil -> true
      wanted -> wanted == watch_profile_id
    end
  end
end
