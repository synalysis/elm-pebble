defmodule Ide.Packages.DependencyResolverTest do
  use ExUnit.Case, async: true

  alias Ide.Packages.DependencyResolver

  test "resolves direct and indirect dependencies" do
    section = %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}}

    callbacks = %{
      versions: fn
        "elm/http" -> {:ok, ["2.0.0"]}
        "elm/url" -> {:ok, ["1.0.0"]}
        "elm/core" -> {:ok, ["1.0.5"]}
      end,
      release: fn
        "elm/http", "2.0.0" ->
          {:ok,
           %{
             "dependencies" => %{
               "elm/core" => "1.0.0 <= v < 2.0.0",
               "elm/url" => "1.0.0 <= v < 2.0.0"
             }
           }}

        "elm/url", "1.0.0" ->
          {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

        "elm/core", "1.0.5" ->
          {:ok, %{"dependencies" => %{}}}
      end
    }

    assert {:ok, resolved} = DependencyResolver.resolve(section, "elm/http", "direct", callbacks)
    assert resolved.direct["elm/http"] == "2.0.0"
    assert resolved.direct["elm/core"] == "1.0.5"
    assert resolved.indirect["elm/url"] == "1.0.0"
  end

  test "detects version conflict across dependency graph" do
    section = %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{}}

    callbacks = %{
      versions: fn
        "elm/http" -> {:ok, ["2.0.0"]}
        "elm/core" -> {:ok, ["1.0.5"]}
      end,
      release: fn
        "elm/http", "2.0.0" ->
          {:ok, %{"dependencies" => %{"elm/core" => "2.0.0 <= v < 3.0.0"}}}

        "elm/core", "1.0.5" ->
          {:ok, %{"dependencies" => %{}}}
      end
    }

    assert {:error, %{kind: :no_compatible_version, package: "elm/core"}} =
             DependencyResolver.resolve(section, "elm/http", "direct", callbacks)
  end

  test "re-resolves graph after removing a direct dependency" do
    section = %{
      "direct" => %{"elm/core" => "1.0.5", "elm/http" => "2.0.0"},
      "indirect" => %{"elm/url" => "1.0.0"}
    }

    callbacks = %{
      versions: fn
        "elm/http" -> {:ok, ["2.0.0"]}
        "elm/url" -> {:ok, ["1.0.0"]}
        "elm/core" -> {:ok, ["1.0.5"]}
      end,
      release: fn
        "elm/http", "2.0.0" ->
          {:ok,
           %{
             "dependencies" => %{
               "elm/core" => "1.0.0 <= v < 2.0.0",
               "elm/url" => "1.0.0 <= v < 2.0.0"
             }
           }}

        "elm/url", "1.0.0" ->
          {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

        "elm/core", "1.0.5" ->
          {:ok, %{"dependencies" => %{}}}
      end
    }

    assert {:ok, resolved} =
             DependencyResolver.resolve_after_removing_direct(section, "elm/http", callbacks)

    assert resolved.direct == %{"elm/core" => "1.0.5"}
    assert resolved.indirect == %{}
    assert resolved.removed == "elm/http"
  end

  test "remove fails when package is not a direct dependency" do
    section = %{"direct" => %{"elm/core" => "1.0.5"}, "indirect" => %{"elm/http" => "2.0.0"}}

    callbacks = %{
      versions: fn _ -> {:ok, ["1.0.0"]} end,
      release: fn _, _ -> {:ok, %{"dependencies" => %{}}} end
    }

    assert {:error, %{kind: :not_direct_dependency, package: "elm/http"}} =
             DependencyResolver.resolve_after_removing_direct(section, "elm/http", callbacks)
  end
end
