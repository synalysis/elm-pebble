defmodule IdeWeb.WorkspaceLive.PublishPageTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Auth.User
  alias Ide.Projects
  alias Ide.Repo

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  defp create_project!(attrs) do
    {:ok, project} = Projects.create_project(attrs)
    project
  end

  defp authenticated_conn(conn, mode) do
    user =
      case mode do
        :public_custom ->
          %User{}
          |> User.email_changeset(%{email: "publish-page-custom@example.test"})
          |> Repo.insert!()

        _ ->
          %User{}
          |> User.changeset(%{firebase_uid: "publish-page-firebase-user"})
          |> Repo.insert!()
      end

    {Plug.Test.init_test_session(conn, user_id: user.id), user}
  end

  test "publish page shows download PBW in local mode", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    project =
      create_project!(%{
        "name" => "PublishDownloadLocal",
        "slug" => "publish-download-local",
        "target_type" => "app"
      })

    assert {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/publish")

    filename = Projects.pbw_download_filename(project)
    assert html =~ "Download #{filename}"
    assert has_element?(view, "a[href='/projects/#{project.slug}/publish/pbw']")
    assert has_element?(view, "a[download='#{filename}']")
    assert html =~ "Install to Watch"
    assert html =~ "Sideload to Watch"
    assert html =~ "Submit to App Store"
    refute html =~ "App Store listing"
  end

  test "publish page shows a permanent App Store listing link when store_app_id is set", %{
    conn: conn
  } do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    project =
      create_project!(%{
        "name" => "PublishListingLink",
        "slug" => "publish-listing-link",
        "target_type" => "watchface",
        "store_app_id" => "classic-motivate"
      })

    assert {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/publish")

    assert html =~ "App Store listing"
    assert html =~ "https://apps.rePebble.com/classic-motivate"

    assert has_element?(
             view,
             "a[href='https://apps.rePebble.com/classic-motivate'][target='_blank']"
           )
  end

  test "publish page shows download PBW and sideload in public_pebble mode", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :public_pebble)
    {conn, user} = authenticated_conn(conn, :public_pebble)

    {:ok, project} =
      Projects.create_project(
        %{
          "name" => "PublishDownloadPebble",
          "slug" => "publish-download-pebble",
          "target_type" => "app"
        },
        user
      )

    assert {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/publish")

    filename = Projects.pbw_download_filename(project)
    assert html =~ "Download #{filename}"
    assert has_element?(view, "a[href='/projects/#{project.slug}/publish/pbw']")
    assert has_element?(view, "a[download='#{filename}']")
    assert html =~ "Sideload to Watch"
    assert html =~ "Submit to App Store"
  end

  test "publish page shows download only without cloud sideload in public_custom mode", %{
    conn: conn
  } do
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)
    {conn, user} = authenticated_conn(conn, :public_custom)

    {:ok, project} =
      Projects.create_project(
        %{
          "name" => "PublishDownloadCustom",
          "slug" => "publish-download-custom",
          "target_type" => "app"
        },
        user
      )

    assert {:ok, view, html} = live(conn, ~p"/projects/#{project.slug}/publish")

    filename = Projects.pbw_download_filename(project)
    assert html =~ "Download #{filename}"
    assert has_element?(view, "a[href='/projects/#{project.slug}/publish/pbw']")
    assert has_element?(view, "a[download='#{filename}']")
    assert html =~ "Automated Rebble App Store submit is not available"
    refute html =~ "Sideload to Watch"
    refute html =~ "Submit to App Store"
  end

  test "sideload event rejects without firebase token", %{conn: conn} do
    Application.put_env(:ide, Ide.Auth, mode: :local)

    project =
      create_project!(%{
        "name" => "PublishSideloadReject",
        "slug" => "publish-sideload-reject",
        "target_type" => "app"
      })

    assert {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/publish")

    render_click(view, "sideload-publish-release")

    html = render(view)
    assert html =~ "CloudPebble login required"
  end
end
