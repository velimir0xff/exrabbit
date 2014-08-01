defmodule Exrabbit.Mixfile do
  use Mix.Project

  def project do
    [ app: :exrabbit,
      version: "0.1.0-dev",
      elixir: "~> 0.14.3",
      deps: deps ]
  end

  def application do
    [
      mod: { Exrabbit.Application, [] },
      applications: [:amqp_client, :rabbit_common]
    ]
  end

  defp deps do
    [
      {:amqp_client, github: "d0rc/amqp_client"},
    ]
  end
end
