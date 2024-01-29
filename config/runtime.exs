import Config

alias Jellyfish.ConfigReader

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.
config :ex_dtls, impl: :nif
config :opentelemetry, traces_exporter: :none

prod? = config_env() == :prod

ip = ConfigReader.read_ip("JF_IP") || Application.fetch_env!(:jellyfish, :ip)

port = ConfigReader.read_port("JF_PORT") || Application.fetch_env!(:jellyfish, :port)

host =
  case System.get_env("JF_HOST") do
    nil -> "#{:inet.ntoa(ip)}:#{port}"
    other -> other
  end

config :jellyfish,
  jwt_max_age: 24 * 3600,
  media_files_path:
    System.get_env("JF_RESOURCES_BASE_PATH", "jellyfish_resources") |> Path.expand(),
  address: host,
  metrics_ip: ConfigReader.read_ip("JF_METRICS_IP") || {127, 0, 0, 1},
  metrics_port: ConfigReader.read_port("JF_METRICS_PORT") || 9568,
  dist_config: ConfigReader.read_dist_config(),
  webrtc_config: ConfigReader.read_webrtc_config()

case System.get_env("JF_SERVER_API_TOKEN") do
  nil when prod? == true ->
    raise """
    environment variable JF_SERVER_API_TOKEN is missing.
    JF_SERVER_API_TOKEN is used for HTTP requests and
    server WebSocket authorization.
    """

  nil ->
    :ok

  token ->
    config :jellyfish, server_api_token: token
end

external_uri = URI.parse("//" <> host)

config :jellyfish, JellyfishWeb.Endpoint,
  secret_key_base:
    System.get_env("JF_SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48)),
  url: [
    host: external_uri.host,
    port: external_uri.port || 443,
    path: external_uri.path || "/"
  ]

# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task: mix phx.gen.cert
case ConfigReader.read_ssl_config() do
  {ssl_key_path, ssl_cert_path} ->
    config :jellyfish, JellyfishWeb.Endpoint,
      https: [
        ip: ip,
        port: port,
        cipher_suite: :strong,
        keyfile: ssl_key_path,
        certfile: ssl_cert_path
      ]

  nil ->
    config :jellyfish, JellyfishWeb.Endpoint, http: [ip: ip, port: port]
end

check_origin = ConfigReader.read_check_origin("JF_CHECK_ORIGIN")

if check_origin != nil do
  config :jellyfish, JellyfishWeb.Endpoint, check_origin: check_origin
end

if prod? do
  config :jellyfish, JellyfishWeb.Endpoint, url: [scheme: "https"]
end
