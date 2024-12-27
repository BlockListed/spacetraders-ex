defmodule Spacetraders.MixProject do
  use Mix.Project

  def project do
    [
      app: :spacetraders,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Spacetraders.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.13"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.19.0"},
      {:dotenvy, "~> 0.9.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
