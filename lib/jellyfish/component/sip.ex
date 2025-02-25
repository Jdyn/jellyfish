defmodule Jellyfish.Component.SIP do
  @moduledoc """
  Module representing the SIP component.
  """

  @behaviour Jellyfish.Endpoint.Config
  use Jellyfish.Component

  alias Membrane.RTC.Engine.Endpoint.SIP
  alias Membrane.RTC.Engine.Endpoint.SIP.RegistrarCredentials

  alias JellyfishWeb.ApiSpec.Component.SIP.Options

  @type properties :: %{
          registrar_credentials: %{
            address: String.t(),
            username: String.t(),
            password: String.t()
          }
        }

  @impl true
  def config(%{engine_pid: engine} = options) do
    sip_config = Application.fetch_env!(:jellyfish, :sip_config)

    external_ip =
      if sip_config[:sip_used?] do
        Application.fetch_env!(:jellyfish, :sip_config)[:sip_external_ip]
      else
        raise """
        SIP components can only be used if JF_SIP_USED environmental variable is set to \"true\"
        """
      end

    with {:ok, serialized_opts} <- serialize_options(options, Options.schema()) do
      endpoint_spec = %SIP{
        rtc_engine: engine,
        external_ip: external_ip,
        registrar_credentials: create_register_credentials(serialized_opts.registrar_credentials)
      }

      properties = serialized_opts

      {:ok, %{endpoint: endpoint_spec, properties: properties}}
    else
      {:error, [%OpenApiSpex.Cast.Error{reason: :missing_field, name: name} | _rest]} ->
        {:error, {:missing_parameter, name}}

      {:error, _reason} = error ->
        error
    end
  end

  defp create_register_credentials(credentials) do
    credentials
    |> Map.to_list()
    |> Keyword.new()
    |> RegistrarCredentials.new()
  end
end
