defmodule Ide.GitHub.RepositoriesTest do
  use ExUnit.Case, async: true

  alias Ide.GitHub.Repositories
  alias Ide.Projects.Project

  test "lookup_status returns not_found for missing repository" do
    request_fun = fn method, url, _headers, _body, _timeout ->
      assert method == :get
      assert url == "https://api.github.com/repos/pebbledev/missing-repo"

      {:ok, %{status: 404, body: %{"message" => "Not Found"}}}
    end

    assert :not_found =
             Repositories.lookup_status(
               %{"owner" => "pebbledev", "repo" => "missing-repo"},
               request_fun: request_fun,
               user_login: "pebbledev"
             )
  end

  test "lookup_status returns exists when repository is present" do
    request_fun = fn :get, _url, _headers, _body, _timeout ->
      {:ok, %{status: 200, body: %{"full_name" => "pebbledev/exists"}}}
    end

    assert :exists =
             Repositories.lookup_status(
               %{"repo" => "exists"},
               request_fun: request_fun,
               user_login: "pebbledev"
             )
  end

  test "create_repository creates a user repository with visibility and description" do
    project = %Project{
      name: "Counter",
      release_defaults: %{"description" => "A counter watchapp"}
    }

    request_fun = fn method, url, _headers, body, _timeout ->
      assert method == :post
      assert url == "https://api.github.com/user/repos"
      assert Jason.decode!(body) == %{
               "name" => "counter-app",
               "private" => true,
               "auto_init" => false,
               "description" => "A counter watchapp"
             }

      {:ok,
       %{
         status: 201,
         body: %{
           "html_url" => "https://github.com/pebbledev/counter-app",
           "private" => true
         }
       }}
    end

    assert {:ok, created} =
             Repositories.create_repository(
               project,
               %{"repo" => "counter-app", "visibility" => "private"},
               request_fun: request_fun,
               user_login: "pebbledev"
             )

    assert created.owner == "pebbledev"
    assert created.repo == "counter-app"
    assert created.html_url =~ "counter-app"
  end

  test "create_repository uses org endpoint when owner differs from user login" do
    project = %Project{name: "Counter", release_defaults: %{}}

    request_fun = fn :post, url, _headers, body, _timeout ->
      assert url == "https://api.github.com/orgs/my-org/repos"
      assert Jason.decode!(body)["name"] == "counter-app"

      {:ok,
       %{status: 201, body: %{"html_url" => "https://github.com/my-org/counter-app", "private" => false}}}
    end

    assert {:ok, created} =
             Repositories.create_repository(
               project,
               %{"owner" => "my-org", "repo" => "counter-app", "visibility" => "public"},
               request_fun: request_fun,
               user_login: "pebbledev"
             )

    assert created.owner == "my-org"
    assert created.private == false
  end

  test "validate_repo_name rejects invalid names" do
    project = %Project{name: "Counter", release_defaults: %{}}

    assert {:error, {:invalid_repo_name, _}} =
             Repositories.create_repository(
               project,
               %{"repo" => "bad name", "visibility" => "private"},
               user_login: "pebbledev"
             )
  end
end
