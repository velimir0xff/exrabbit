defmodule Exrabbit.Mixfile do
  use Mix.Project

  def project do
    [ app: :exrabbit,
      version: "0.9.0-alpha",
      elixir: "~> 0.14.3",
      deps: deps ]
  end

  def application do
    [
      mod: { Exrabbit.Application, [] },
      applications: [:amqp_client, :rabbit_common, :jazz]
    ]
  end

  defp deps do
    [
      {:amqp_client, github: "issuu/amqp_client"},
      {:jazz, "~> 0.1.2"},
    ]
  end
end
