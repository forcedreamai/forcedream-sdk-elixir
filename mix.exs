defmodule ForceDream.MixProject do
  use Mix.Project

  def project do
    [
      app: :forcedream,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Search, invoke, and cryptographically verify AI agents on ForceDream.",
      package: package(),
      source_url: "https://github.com/forcedreamai/forcedream-sdk-elixir"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/forcedreamai/forcedream-sdk-elixir"}
    ]
  end
end
