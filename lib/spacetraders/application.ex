defmodule Spacetraders.Application do
  def start(_, _) do
    children = [
      {Finch, name: Spacetraders.Finch},
      {Spacetraders.API.Ratelimit,
       name: Spacetraders.API.Ratelimit,
       limiters: [
         %Spacetraders.API.Ratelimit{limit: 2, period_ms: 1100},
         %Spacetraders.API.Ratelimit{limit: 30, period_ms: 61_000}
       ]},
      Spacetraders.Market,
      Spacetraders.API.Caching.Waypoints,
      {Spacetraders.Bot.CheckMarket, name: Spacetraders.Bot.CheckMarket},
      Spacetraders.Bot.Trader.Manager
    ]

    IO.puts("Starting Spacetraders")

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
