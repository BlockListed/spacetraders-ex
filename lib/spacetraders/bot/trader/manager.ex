defmodule Spacetraders.Bot.Trader.Manager do
  alias Spacetraders.API
  use Supervisor

  @tradesupervisor Spacetraders.Bot.Trader.Manager.TradeSupervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {DynamicSupervisor, name: @tradesupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def do_trading(ship, system, avail_funds \\ 50_000) do
    {:ok, ship_data} = API.get_ship(ship)

    true = ship_data["nav"]["systemSymbol"] == system

    route = Spacetraders.Bot.Trader.Planner.plan(system)

    DynamicSupervisor.start_child(@tradesupervisor, {
      Spacetraders.Bot.Trader,
      ship: ship, trade_route: route, funds: avail_funds
    })
  end
end