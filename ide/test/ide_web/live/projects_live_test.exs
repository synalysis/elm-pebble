defmodule IdeWeb.ProjectsLiveTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Auth
  alias Ide.Auth.User
  alias Ide.GitHub.Credentials
  alias Ide.Projects
  alias Ide.Repo

  setup do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_projects_live_github_#{System.unique_integer([:positive])}.json"
      )

    original_auth = Application.get_env(:ide, Ide.Auth, [])
    original_github = Application.get_env(:ide, Ide.GitHub, [])
    Application.put_env(:ide, Ide.GitHub, credentials_path: temp_path)
    Credentials.clear()

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, original_auth)
      Application.put_env(:ide, Ide.GitHub, original_github)
      File.rm(temp_path)
    end)

    :ok
  end

  test "projects page shows GitHub import option in import panel", %{conn: conn} do
    assert {:ok, view, html} = live(conn, ~p"/projects")
    assert html =~ "Import"
    assert html =~ "run this IDE locally"
    assert html =~ "https://github.com/synalysis/elm-pebble"

    view |> element("button", "Import") |> render_click()
    html = view |> element("button", "From GitHub") |> render_click()

    assert html =~ "From folder"
    assert html =~ "From GitHub"
    assert html =~ "Repository URL"
    assert html =~ "Import from GitHub"
  end

  test "GitHub import submit is disabled when GitHub is not connected", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/projects")

    view |> element("button", "Import") |> render_click()
    html = view |> element("button", "From GitHub") |> render_click()

    assert html =~ "Connect GitHub"
    assert html =~ "Import from GitHub"
    assert html =~ "disabled"
  end

  test "public mode shows delete data section for signed-in users", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    {:ok, user} =
      %User{}
      |> User.email_changeset(%{email: "delete-ui@example.test"})
      |> Repo.insert()

    conn =
      conn
      |> Plug.Test.init_test_session(user_id: user.id)
      |> get(~p"/projects")

    assert html_response(conn, 200) =~ "Delete my data"
    assert html_response(conn, 200) =~ "Delete your data"
    assert html_response(conn, 200) =~ ~p"/auth/delete-data"
  end

  test "local mode hides delete data section", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    conn = get(conn, ~p"/projects")

    refute html_response(conn, 200) =~ "Delete my data"
  end

  test "create project shows slug error when slug already exists", %{conn: conn} do
    assert {:ok, _project} =
             Projects.create_project(%{
               "name" => "Digital",
               "slug" => "digital",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    assert {:ok, view, _html} = live(conn, ~p"/projects")

    view |> element("button", "Create project") |> render_click()
    view |> element("button[phx-value-template='watchface-digital']") |> render_click()

    html =
      view
      |> form("#project-form", %{
        "project" => %{
          "name" => "Digital"
        }
      })
      |> render_submit()

    assert html =~ "Could not create project"
    assert html =~ "id=\"project-form\""
  end

  test "create project modal groups templates by category", %{conn: conn} do
    assert {:ok, view, html} = live(conn, ~p"/projects")
    refute html =~ "Watchfaces"

    html = view |> element("button", "Create project") |> render_click()

    assert html =~ "Create project"
    assert html =~ "Watchfaces"
    assert html =~ "Companion demos"
    assert html =~ "Watch demos"
    assert html =~ "Games"
    assert html =~ "/images/template-previews/watchface-digital.png"
  end

  test "create project submit stays disabled until a project name is entered", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/projects")

    view |> element("button", "Create project") |> render_click()
    refute has_element?(view, "button[form='project-form'][disabled]")

    view
    |> form("#project-form", %{"project" => %{"name" => ""}})
    |> render_change()

    assert has_element?(view, "button[form='project-form'][disabled]")
  end

  test "selecting a template autofills the project name when empty", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/projects")

    view |> element("button", "Create project") |> render_click()

    view
    |> form("#project-form", %{"project" => %{"name" => ""}})
    |> render_change()

    html =
      view
      |> element("button[phx-value-template='watchface-digital']")
      |> render_click()

    assert html =~ ~s(value="Digital")
    refute has_element?(view, "button[form='project-form'][disabled]")
  end

  test "opening create modal prefills name from default starter template", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/projects")

    html = view |> element("button", "Create project") |> render_click()

    assert html =~ ~s(value="Starter")
    refute has_element?(view, "button[form='project-form'][disabled]")
  end

  test "delete my data removes account and redirects to login", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    {:ok, user} =
      %User{}
      |> User.email_changeset(%{email: "delete-action@example.test"})
      |> Repo.insert()

    assert {:ok, _project} =
             Projects.create_project(
               %{
                 "name" => "Delete Action",
                 "slug" => "delete-action",
                 "target_type" => "app"
               },
               user
             )

    conn =
      conn
      |> Plug.Test.init_test_session(user_id: user.id)
      |> post(~p"/auth/delete-data", %{})

    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your account data has been deleted"
    refute get_session(conn, :user_id)
    refute Repo.get(User, user.id)
    refute Auth.get_user(user.id)
  end
end
