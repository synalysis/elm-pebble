defmodule Ide.AppStore.PublisherTest do
  use ExUnit.Case, async: false

  alias Ide.AppStore.Publisher

  test "publishes an existing app release through dashboard API" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_appstore_publisher_test_#{System.unique_integer([:positive])}"
      )

    app_root = Path.join(root, "app")
    build_root = Path.join(app_root, "build")
    File.mkdir_p!(build_root)
    on_exit(fn -> File.rm_rf(root) end)

    pbw_path = Path.join(build_root, "app.pbw")
    screenshot_path = Path.join(root, "basalt_shot_1.png")
    File.write!(pbw_path, "pbw")
    File.write!(screenshot_path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

    File.write!(
      Path.join(app_root, "package.json"),
      Jason.encode!(%{
        "name" => "tangram",
        "version" => "1.0.1",
        "pebble" => %{
          "displayName" => "Tangram",
          "uuid" => "35d51bb9-42ee-4152-8f19-ba81e9db37fd",
          "targetPlatforms" => ["basalt"],
          "watchapp" => %{"watchface" => true}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, headers, body, _timeout ->
      body = if is_nil(body), do: "", else: IO.iodata_to_binary(body)
      Agent.update(agent, &[{method, url, headers, body} | &1])

      cond do
        method == :get and String.ends_with?(url, "/api/v1/developer/me") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "developer" => %{"id" => "dev"},
               "app_lookup" => %{
                 "by_app_uuid" => %{"35d51bb9-42ee-4152-8f19-ba81e9db37fd" => "app-id"}
               }
             }
           }}

        method == :post and String.ends_with?(url, "/api/dashboard/apps/app-id/releases") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "message" => "ok",
               "screenshotResults" => %{"uploaded" => [%{"platform" => "basalt"}]}
             }
           }}
      end
    end

    assert {:ok, result} =
             Publisher.publish(
               %{name: "Tangram"},
               app_root: app_root,
               artifact_path: pbw_path,
               version: "1.0.1",
               release_notes: "Added screenshots",
               screenshots: [screenshot_path],
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun
             )

    assert result.status == :ok
    assert result.output =~ "Resolved existing appstore app ID: app-id"
    assert result.output =~ "Uploaded screenshots: 1"

    calls = Agent.get(agent, &Enum.reverse/1)
    assert [_me_call, {:post, release_url, headers, release_body}] = calls
    assert release_url == "https://example.test/api/dashboard/apps/app-id/releases"

    assert Enum.any?(headers, fn {key, value} ->
             key == "authorization" and value == "Bearer token"
           end)

    assert release_body =~ ~s(name="version")
    assert release_body =~ "1.0.1"
    assert release_body =~ ~s(name="isPublished")
    assert release_body =~ "true"
    assert release_body =~ ~s(name="replaceScreenshots")
    assert release_body =~ "true"
    assert release_body =~ ~s(name="screenshots_basalt"; filename="basalt_shot_1.png")
    assert release_body =~ ~s(name="pbwFile"; filename="app.pbw")
  end
end
