defmodule Spacetraders.Bot.Trader.Planner do
  alias Spacetraders.API

  defmodule Market do
    @enforce_keys [:symbol, :trade]
    defstruct [:symbol, :trade]

    @type t :: %Market{symbol: String.t(), trade: map()}

    @type trade_route :: {t(), t()}
  end

  def plan(system) do
    markets = Spacetraders.Market.get_all_in_system(system)

    import_map =
      Enum.reduce(markets, %{}, fn market, acc ->
        market["imports"]
        |> Enum.map(& &1["symbol"])
        |> Enum.reduce(acc, fn import, acc when is_binary(import) ->
          market_location = market["symbol"]
          trade = Enum.find(market["tradeGoods"], &(&1["symbol"] == import))

          if Map.has_key?(acc, import) do
            Map.update!(acc, import, &[%Market{symbol: market_location, trade: trade} | &1])
          else
            Map.put(acc, import, [%Market{symbol: market_location, trade: trade}])
          end
        end)
      end)

    trade_routes =
      Stream.map(markets, fn market ->
        Stream.filter(market["tradeGoods"], &(&1["type"] == "EXPORT"))
        |> Stream.map(&%Market{symbol: market["symbol"], trade: &1})
        |> Stream.map(fn trade ->
          Map.get(import_map, trade.trade["symbol"], [])
          |> Stream.map(&{trade, &1})
        end)
      end)
      |> Stream.concat()
      |> Stream.concat()
      |> Enum.to_list()

    highest_profit = get_best_trade_route_by(trade_routes, &get_profit_per_unit/1)
    best_margin = get_best_trade_route_by(trade_routes, &get_margin/1)
    highest_profit_per_dist = get_best_trade_route_by(trade_routes, &(get_profit_per_unit(&1)/get_distance(&1)))

    highest_profit |> dbg
    best_margin |> dbg
    highest_profit_per_dist |> dbg
  end

  @spec get_best_trade_route_by([Market.trade_route()], (Market.trade_route() -> number())) ::
          Market.trade_route()
  def get_best_trade_route_by(trade_routes, fun) do
    Enum.max_by(trade_routes, fun)
  end

  @spec get_profit_per_unit(Market.trade_route()) :: number()
  def get_profit_per_unit({from, to}) do
    to.trade["sellPrice"] - from.trade["purchasePrice"]
  end

  @spec get_margin(Market.trade_route()) :: number()
  def get_margin({from, to}) do
    cogs = from.trade["purchasePrice"]
    sale_price = to.trade["sellPrice"]

    (sale_price - cogs) / sale_price * 100
  end

  @spec get_distance(Market.trade_route()) :: number()
  def get_distance({from, to}) do
    from = from.symbol
    to = to.symbol

    API.distance_between(from, to)
  end
end
