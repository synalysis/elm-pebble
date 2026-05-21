defmodule Ide.Auth.DeleteUserDataTest do
  use Ide.DataCase, async: false

  alias Ide.Auth
  alias Ide.Auth.LoginToken
  alias Ide.Auth.User
  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Repo

  setup do
    root = Path.join(System.tmp_dir!(), "ide_delete_user_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "delete_user_data removes account, projects, tokens, and workspace files" do
    {:ok, user} =
      %User{}
      |> User.email_changeset(%{email: "delete-me@example.test"})
      |> Repo.insert()

    assert {:ok, project} =
             Projects.create_project(
               %{
                 "name" => "Owned Project",
                 "slug" => "owned-project",
                 "target_type" => "app"
               },
               user
             )

    workspace_path = Projects.project_workspace_path(project)

    assert File.dir?(workspace_path)

    expires_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    assert {:ok, _token} =
             %LoginToken{}
             |> LoginToken.changeset(%{
               user_id: user.id,
               token_hash: "test-token-hash",
               expires_at: expires_at
             })
             |> Repo.insert()

    assert :ok = Auth.delete_user_data(user)

    refute Repo.get(User, user.id)
    refute Repo.get(Project, project.id)
    refute Repo.get_by(LoginToken, user_id: user.id)
    refute File.exists?(workspace_path)
    refute File.exists?(Path.dirname(workspace_path))
  end
end
