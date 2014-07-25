defmodule Exrabbit.Mixfile do
  use Mix.Project

  def project do
    [ app: :exrabbit,
      version: "0.0.5",
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
      {:amqp_client, github: "d0rc/amqp_client"},
      {:jazz, github: "meh/jazz"},
    ]
  end
end
