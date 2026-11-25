defmodule StudioPlayground.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        StudioPlaygroundWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:studio_playground, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: StudioPlayground.PubSub},
        StudioPlayground.Jido
      ] ++ demo_agents() ++ [StudioPlaygroundWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StudioPlayground.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp demo_agents do
    if Application.get_env(:studio_playground, :demo_agents, false) do
      [{Task, &StudioPlayground.DemoAgents.start!/0}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StudioPlaygroundWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
