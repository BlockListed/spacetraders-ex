defmodule Spacetraders.Bot.Trader.Planner do
  alias Spacetraders.API

  defmodule Market do
    @enforce_keys [:symbol, :trade]
    defstruct [:symbol, :trade]

    @type t :: %Market{symbol: String.t(), trade: map()}

    @type trade_route :: {t(), t()}

    @spec update_trade_route(trade_route()) :: trade_route()
    def update_trade_route({from, to}) do
      trade_good = from.trade["symbol"]

      {:some, buy_market} = Spacetraders.Market.get(from.symbol)
      {:some, sell_market} = Spacetraders.Market.get(to.symbol)

      buy_trade = Enum.find(buy_market["tradeGoods"], &(&1["symbol"] == trade_good)) |> dbg
      sell_trade = Enum.find(sell_market["tradeGoods"], &(&1["symbol"] == trade_good)) |> dbg

      {%Market{from | trade: buy_trade}, %Market{to | trade: sell_trade}} |> dbg
    end
  end

  @spec plan(String.t()) :: Market.trade_route()
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

    highest_profit_per_dist =
      get_best_trade_route_by(trade_routes, &(get_profit_per_unit(&1) / get_distance(&1)))

    highest_profit_per_dist
  end

  @spec get_best_trade_route_by([Market.trade_route()], (Market.trade_route() -> number())) ::
          Market.trade_route()
  defp get_best_trade_route_by(trade_routes, fun) do
    Enum.max_by(trade_routes, fun)
  end

  @spec get_profit_per_unit(Market.trade_route()) :: number()
  def get_profit_per_unit({from, to}) do
    to.trade["sellPrice"] - from.trade["purchasePrice"]
  end

  @spec get_distance(Market.trade_route()) :: number()
  def get_distance({from, to}) do
    from = from.symbol
    to = to.symbol

    API.distance_between(from, to)
  end
end
