defmodule Spacetraders.Bot.Trader.Planner do
  alias Spacetraders.API

  defmodule Market do
    @enforce_keys [:symbol, :trade]
    defstruct [:symbol, :trade]

    @type t :: %Market{symbol: String.t(), trade: map()}

    @type tr :: {t(), t()}

    defmodule TradeRoute do
      alias Spacetraders.Model
      @enforce_keys [:symbol, :from, :to]
      defstruct [:symbol, :from, :to]

      @type t :: %TradeRoute{symbol: String.t(), from: String.t(), to: String.t()}

      @spec buy_volume(t()) :: number()
      def buy_volume(%TradeRoute{} = route) do
        {:some, market} = Spacetraders.Market.get(route.from)

        {:some, trade} = Model.Market.get_trade(market, route.symbol)

        trade["tradeVolume"]
      end

      @spec buy_price(t()) :: number()
      def buy_price(%TradeRoute{} = route) do
        {:some, market} = Spacetraders.Market.get(route.from)

        {:some, trade} = Model.Market.get_trade(market, route.symbol)

        trade["purchasePrice"]
      end

      @spec sell_volume(t()) :: number()
      def sell_volume(%TradeRoute{} = route) do
        {:some, market} = Spacetraders.Market.get(route.to)

        {:some, trade} = Model.Market.get_trade(market, route.symbol)

        trade["tradeVolume"]
      end

      @spec buy_price(t()) :: number()
      def sell_price(%TradeRoute{} = route) do
        {:some, market} = Spacetraders.Market.get(route.to)

        {:some, trade} = Model.Market.get_trade(market, route.symbol)

        trade["sellPrice"]
      end

      @spec profit(t()) :: number()
      def profit(route) do
        {:some, buy_market} = Spacetraders.Market.get(route.from)
        {:some, sell_market} = Spacetraders.Market.get(route.to)

        {:some, buy_trade} = Model.Market.get_trade(buy_market, route.symbol)
        {:some, sell_trade} = Model.Market.get_trade(sell_market, route.symbol)

        buy = %Spacetraders.Bot.Trader.Planner.Market{
          symbol: buy_market["symbol"],
          trade: buy_trade
        }

        sell = %Spacetraders.Bot.Trader.Planner.Market{
          symbol: sell_market["symbol"],
          trade: sell_trade
        }

        Spacetraders.Bot.Trader.Planner.get_profit_per_unit({buy, sell})
      end

      @spec from_tr(Spacetraders.Bot.Trader.Planner.Market.tr()) :: t()
      def from_tr(tr) do
        {from, to} = tr
        symbol = from.trade["symbol"]

        from = from.symbol
        to = to.symbol

        %TradeRoute{symbol: symbol, from: from, to: to}
      end
    end
  end

  @spec plan(String.t()) :: Market.TradeRoute.t()
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

    Market.TradeRoute.from_tr(highest_profit_per_dist)
  end

  @spec get_best_trade_route_by([Market.tr()], (Market.tr() -> number())) ::
          Market.tr()
  defp get_best_trade_route_by(trade_routes, fun) do
    Enum.max_by(trade_routes, fun)
  end

  @spec get_profit_per_unit(Market.tr()) :: number()
  def get_profit_per_unit({from, to}) do
    to.trade["sellPrice"] - from.trade["purchasePrice"]
  end

  @spec get_distance(Market.tr()) :: number()
  def get_distance({from, to}) do
    from = from.symbol
    to = to.symbol

    API.distance_between(from, to)
  end
end
