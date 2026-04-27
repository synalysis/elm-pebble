defmodule Ide.Packages.WatchCompatibilityTest do
  use ExUnit.Case, async: false

  alias Ide.Packages.WatchCompatibility

  defmodule StubProvider do
    @moduledoc false
    @behaviour Ide.Packages.Provider

    def search(_, _), do: {:ok, []}
    def package_details(_, _), do: {:error, :noop}
    def readme(_, _, _), do: {:error, :noop}

    def versions("user/webish", _), do: {:ok, ["1.0.0"]}
    def versions("user/clean", _), do: {:ok, ["1.0.0"]}
    def versions("elm/html", _), do: {:ok, ["2.0.1"]}
    def versions("elm/virtual-dom", _), do: {:ok, ["1.0.3"]}
    def versions("elm/core", _), do: {:ok, ["1.0.5"]}
    def versions(_, _), do: {:ok, ["1.0.0"]}

    def package_release("user/webish", "1.0.0", _) do
      {:ok, %{"dependencies" => %{"elm/html" => "1.0.0 <= v < 3.0.0"}}}
    end

    def package_release("user/clean", "1.0.0", _) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm/html", "2.0.1", _) do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/virtual-dom" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/virtual-dom", "1.0.3", _) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm/core", "1.0.5", _), do: {:ok, %{"dependencies" => %{}}}
    def package_release(_, _, _), do: {:ok, %{"dependencies" => %{}}}
  end

  setup do
    WatchCompatibility.clear_cache!()
    :ok
  end

  test "drops catalog entries whose dependency tree includes the web/DOM stack" do
    provider = %{module: StubProvider, opts: []}

    entries = [
      %{name: "user/clean", summary: "ok"},
      %{name: "user/webish", summary: "uses html"},
      %{name: "elm/html", summary: "DOM"}
    ]

    kept = WatchCompatibility.filter_entries(entries, provider)
    names = kept |> Enum.map(& &1.name) |> Enum.sort()
    assert names == ["user/clean"]
  end
end
