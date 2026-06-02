defmodule Ide.AppStore.ListingTest do
  use ExUnit.Case, async: true

  alias Ide.AppStore.Listing

  test "updates listing via developer portal API and package.json" do
    project = %{
      name: "Listing Sync",
      store_app_id: "store-app-1",
      app_uuid: "35d51bb9-42ee-4152-8f19-ba81e9db37fd",
      release_defaults: %{
        "description" => "A test description",
        "website_url" => "https://example.dev",
        "source_url" => "https://github.com/example/repo",
        "tags" => "fitness, utility",
        "capabilities" => ["health"],
        "target_platforms" => ["basalt"]
      }
    }

    root =
      Path.join(
        System.tmp_dir!(),
        "ide_listing_test_#{System.unique_integer([:positive])}"
      )

    package_dir = Path.join(root, ".pebble-sdk/app")
    File.mkdir_p!(package_dir)
    on_exit(fn -> File.rm_rf(root) end)

    File.write!(
      Path.join(package_dir, "package.json"),
      Jason.encode!(%{
        "name" => "listing-sync",
        "keywords" => ["pebble-app"],
        "pebble" => %{
          "uuid" => "35d51bb9-42ee-4152-8f19-ba81e9db37fd",
          "targetPlatforms" => ["aplite"],
          "watchapp" => %{"watchface" => false}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, _headers, body, _timeout ->
      body = if is_nil(body), do: "", else: body
      Agent.update(agent, &[{method, url, body} | &1])
      {:ok, %{status: 200, body: %{"success" => true, "id" => "store-app-1"}}}
    end

    assert {:ok, result} =
             Listing.update_metadata(project,
               workspace_root: root,
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun
             )

    assert result.status == :ok
    assert result.output =~ "App Store listing updated"
    assert result.project_attrs == %{}

    calls = Agent.get(agent, &Enum.reverse/1)
    assert [{:post, url, posted_body}] = calls
    assert url == "https://example.test/api/dp/app/store-app-1"

    assert %{
             "title" => "Listing Sync",
             "description" => "A test description",
             "website" => "https://example.dev",
             "source" => "https://github.com/example/repo"
           } = Jason.decode!(posted_body)

    {:ok, raw} = File.read(Path.join(package_dir, "package.json"))
    {:ok, package} = Jason.decode(raw)
    assert package["description"] == "A test description"
    assert package["keywords"] == ["pebble-app", "fitness", "utility"]
    assert get_in(package, ["pebble", "capabilities"]) == ["health"]
    assert get_in(package, ["pebble", "targetPlatforms"]) == ["basalt"]
  end

  test "resolves uuid from elm-pebble.project.json without package.json" do
    project = %{
      name: "Manifest UUID",
      slug: "manifest-uuid",
      release_defaults: %{"description" => "From manifest"}
    }

    root =
      Path.join(
        System.tmp_dir!(),
        "ide_listing_manifest_uuid_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    uuid = "35d51bb9-42ee-4152-8f19-ba81e9db37fd"

    File.write!(
      Path.join(root, "elm-pebble.project.json"),
      Jason.encode!(%{
        "schema_version" => 1,
        "name" => "Manifest UUID",
        "slug" => "manifest-uuid",
        "target_type" => "watchface",
        "source_roots" => ["watch"],
        "import_path" => ".",
        "app_uuid" => uuid
      })
    )

    request_fun = fn
      :get, _url, _, _, _ ->
        {:ok,
         %{
           status: 200,
           body: %{
             "developer" => %{"id" => "dev"},
             "app_lookup" => %{"by_app_uuid" => %{uuid => "manifest-resolved-id"}}
           }
         }}

      :post, url, _, _, _ ->
        assert String.contains?(url, "/api/dp/app/manifest-resolved-id")
        {:ok, %{status: 200, body: %{"success" => true}}}
    end

    assert {:ok, result} =
             Listing.update_metadata(project,
               workspace_root: root,
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun
             )

    assert result.status == :ok

    assert result.project_attrs == %{
             "store_app_id" => "manifest-resolved-id",
             "app_uuid" => uuid
           }
  end

  test "resolves app id from developer me when store_app_id is blank" do
    project = %{
      name: "Listing Resolve",
      app_uuid: "35D51BB9-42EE-4152-8F19-BA81E9DB37FD",
      release_defaults: %{"description" => "Face"}
    }

    request_fun = fn
      :get, url, _, _, _ ->
        assert String.ends_with?(url, "/api/v1/developer/me")

        {:ok,
         %{
           status: 200,
           body: %{
             "developer" => %{"id" => "dev"},
             "app_lookup" => %{
               "by_app_uuid" => %{"35d51bb9-42ee-4152-8f19-ba81e9db37fd" => "resolved-id"}
             }
           }
         }}

      :post, url, _, _, _ ->
        assert String.contains?(url, "/api/dp/app/resolved-id")
        {:ok, %{status: 200, body: %{"success" => true}}}
    end

    assert {:ok, result} =
             Listing.update_metadata(project,
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun
             )

    assert result.status == :ok
    assert result.project_attrs == %{"store_app_id" => "resolved-id"}
    assert result.output =~ "resolved-id"
  end
end
