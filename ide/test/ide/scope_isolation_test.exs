defmodule Ide.ScopeIsolationTest do
  use Ide.DataCase, async: false

  alias Ide.Auth.User
  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.Debugger
  alias Ide.Projects

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_scope_isolation_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "compiler cache and debugger state are isolated for same slug across owners" do
    {:ok, alice} =
      %User{}
      |> User.changeset(%{firebase_uid: "scope-alice"})
      |> Repo.insert()

    {:ok, bob} =
      %User{}
      |> User.changeset(%{firebase_uid: "scope-bob"})
      |> Repo.insert()

    {:ok, alice_project} =
      Projects.create_project(
        %{"name" => "Shared Slug", "slug" => "shared-scope", "target_type" => "app"},
        alice
      )

    {:ok, bob_project} =
      Projects.create_project(
        %{"name" => "Shared Slug", "slug" => "shared-scope", "target_type" => "app"},
        bob
      )

    alice_key = Projects.scope_key(alice_project)
    bob_key = Projects.scope_key(bob_project)

    on_exit(fn ->
      Debugger.forget_project(alice_key)
      Debugger.forget_project(bob_key)
    end)

    assert :ok = CompileCache.put(alice_key, "rev-a", %{status: :ok, output: "alice"})
    assert :ok = CompileCache.put(bob_key, "rev-b", %{status: :error, output: "bob"})

    assert {:ok, %{result: %{output: "alice"}}} = CompileCache.get(alice_key, "rev-a")
    assert {:ok, %{result: %{output: "bob"}}} = CompileCache.get(bob_key, "rev-b")
    assert {:error, :not_found} = CompileCache.get(alice_key, "rev-b")

    assert {:ok, _} = Debugger.start_session(alice_key)
    assert {:ok, _} = Debugger.start_session(bob_key)

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(alice_key, %{
               status: :ok,
               compiled_path: "/alice/path",
               revision: "alice-rev",
               cached: true,
               error_count: 0,
               warning_count: 0,
               diagnostics: [],
               source_root: "watch"
             })

    assert {:ok, _} =
             Debugger.ingest_elmc_compile(bob_key, %{
               status: :ok,
               compiled_path: "/bob/path",
               revision: "bob-rev",
               cached: false,
               error_count: 0,
               warning_count: 0,
               diagnostics: [],
               source_root: "watch"
             })

    assert {:ok, alice_snapshot} = Debugger.snapshot(alice_key, event_limit: 1)
    assert {:ok, bob_snapshot} = Debugger.snapshot(bob_key, event_limit: 1)

    assert get_in(alice_snapshot, [:watch, :model, "elmc_compile_revision"]) == "alice-rev"
    assert get_in(bob_snapshot, [:watch, :model, "elmc_compile_revision"]) == "bob-rev"
  end
end
