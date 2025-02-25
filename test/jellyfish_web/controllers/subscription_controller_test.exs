defmodule JellyfishWeb.SubscriptionControllerTest do
  use JellyfishWeb.ConnCase

  @s3_credentials %{
    accessKeyId: "access_key_id",
    secretAccessKey: "secret_access_key",
    region: "region",
    bucket: "bucket"
  }

  @sip_credentials %{
    address: "my-sip-registrar.net",
    username: "user-name",
    password: "pass-word"
  }

  setup %{conn: conn} do
    server_api_token = Application.fetch_env!(:jellyfish, :server_api_token)
    conn = put_req_header(conn, "authorization", "Bearer " <> server_api_token)
    conn = put_req_header(conn, "accept", "application/json")

    conn = post(conn, ~p"/room", videoCodec: "h264")
    assert %{"id" => id} = json_response(conn, :created)["data"]["room"]

    on_exit(fn ->
      conn = delete(conn, ~p"/room/#{id}")
      assert response(conn, :no_content)
    end)

    {:ok, %{conn: conn, room_id: id}}
  end

  describe "subscription overall" do
    test "returns error when room doesn't exist", %{conn: conn} do
      conn =
        post(conn, ~p"/room/invalid_room_id/component/invalid_component_id/subscribe/",
          origins: ["peer-1", "rtsp-2"]
        )

      assert json_response(conn, :not_found)["errors"] == "Room invalid_room_id does not exist"
    end

    test "returns error when hls component doesn't exist", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component/invalid_component_id/subscribe/",
          origins: ["peer-1", "file-2"]
        )

      assert json_response(conn, :bad_request)["errors"] ==
               "Component invalid_component_id does not exist"
    end

    test "returns error when subscribe on component that is not HLS or Recording", %{
      conn: conn,
      room_id: room_id
    } do
      Application.put_env(:jellyfish, :sip_config, sip_used?: true, sip_external_ip: "127.0.0.1")

      on_exit(fn ->
        Application.put_env(:jellyfish, :sip_config, sip_used?: false, sip_external_ip: nil)
      end)

      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "sip",
          options: %{registrarCredentials: @sip_credentials}
        )

      assert %{
               "data" => %{
                 "id" => id,
                 "type" => "sip"
               }
             } = json_response(conn, :created)

      conn =
        post(conn, ~p"/room/#{room_id}/component/#{id}/subscribe/", origins: ["peer-1", "file-2"])

      assert json_response(conn, :bad_request)["errors"] ==
               "Subscribe mode is supported only for HLS and Recording components"
    end
  end

  describe "hls endpoint tests" do
    test "returns error when subscribe mode is :auto", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "hls",
          options: %{subscribeMode: "auto"}
        )

      assert %{
               "data" => %{
                 "id" => id,
                 "type" => "hls",
                 "properties" => %{"subscribeMode" => "auto"}
               }
             } = json_response(conn, :created)

      conn =
        post(conn, ~p"/room/#{room_id}/component/#{id}/subscribe", origins: ["peer-1", "rtsp-2"])

      assert json_response(conn, :bad_request)["errors"] ==
               "Component #{id} option `subscribe_mode` is set to :auto"
    end

    test "return success when subscribe mode is :manual", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "hls",
          options: %{subscribeMode: "manual"}
        )

      assert %{
               "data" => %{
                 "id" => id,
                 "type" => "hls",
                 "properties" => %{"subscribeMode" => "manual"}
               }
             } = json_response(conn, :created)

      conn =
        post(conn, ~p"/room/#{room_id}/component/#{id}/subscribe", origins: ["peer-1", "file-2"])

      assert response(conn, :created) == "Successfully subscribed for tracks"
    end
  end

  describe "recording endpoint tests" do
    test "returns error when subscribe mode is :auto", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "recording",
          options: %{credentials: Enum.into(@s3_credentials, %{}), subscribeMode: "auto"}
        )

      assert %{
               "data" => %{
                 "id" => id,
                 "type" => "recording",
                 "properties" => %{"subscribeMode" => "auto"}
               }
             } = json_response(conn, :created)

      conn =
        post(conn, ~p"/room/#{room_id}/component/#{id}/subscribe", origins: ["peer-1", "rtsp-2"])

      assert json_response(conn, :bad_request)["errors"] ==
               "Component #{id} option `subscribe_mode` is set to :auto"
    end

    test "return success when subscribe mode is :manual", %{conn: conn, room_id: room_id} do
      conn =
        post(conn, ~p"/room/#{room_id}/component",
          type: "recording",
          options: %{credentials: Enum.into(@s3_credentials, %{}), subscribeMode: "manual"}
        )

      assert %{
               "data" => %{
                 "id" => id,
                 "type" => "recording",
                 "properties" => %{"subscribeMode" => "manual"}
               }
             } = json_response(conn, :created)

      conn =
        post(conn, ~p"/room/#{room_id}/component/#{id}/subscribe", origins: ["peer-1", "file-2"])

      assert response(conn, :created) == "Successfully subscribed for tracks"
    end
  end
end
