defmodule Spacetraders.Bot.Trader.Planner do
  alias Spacetraders.API

  defmodule Market do
    @enforce_keys [:symbol, :trade]
    defstruct [:symbol, :trade]
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
      end) |> Enum.to_list()

    trade_routes |> dbg
  end
end
