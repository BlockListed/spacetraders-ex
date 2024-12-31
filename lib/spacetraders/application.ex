defmodule Spacetraders.Application do
  def configure_agent() do
    {:ok, agent} = Spacetraders.API.agent()
    symbol = agent["symbol"]

    Application.put_env(:spacetraders, :agent, symbol)
  end

  def start(_, _) do
    children = [
      {Finch, name: Spacetraders.Finch},
      {Spacetraders.API.Ratelimit,
       name: Spacetraders.API.Ratelimit,
       limiters: [
         %Spacetraders.API.Ratelimit{limit: 2, period_ms: 1100},
         %Spacetraders.API.Ratelimit{limit: 30, period_ms: 61_000}
       ]},
      Supervisor.child_spec({Task, &configure_agent/0}, id: Spacetraders.Agent.Configure),
      Spacetraders.Market,
      Spacetraders.API.Caching.Waypoints,
      Spacetraders.Bot.MarketChecker.Manager,
      Spacetraders.Bot.Trader.Manager,
      Spacetraders.Accounting
    ]

    IO.puts("Starting Spacetraders")

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
