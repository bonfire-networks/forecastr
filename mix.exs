defmodule Forecastr.MixProject do
  use Mix.Project

  def project do
    [
      app: :forecastr,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      dialyzer: [plt_file: ".dialyzer/local.plt"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Forecastr.Application, []}
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.0"},
      {:poison, "~> 3.1"},
      {:table, "~> 0.0.5"},
      {:dialyxir, "~> 0.5.1", only: [:dev], runtime: false},
      {:credo, "~> 0.9.0-rc1", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
