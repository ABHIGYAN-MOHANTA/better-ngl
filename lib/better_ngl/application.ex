defmodule BetterNgl.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(:chat_messages, [:set, :public, :named_table, :duplicate_bag])

    children = [
      BetterNglWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:better_ngl, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BetterNgl.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: BetterNgl.Finch},
      # Start a worker by calling: BetterNgl.Worker.start_link(arg)
      # {BetterNgl.Worker, arg},
      # Start to serve requests, typically the last entry
      BetterNglWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BetterNgl.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BetterNglWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
