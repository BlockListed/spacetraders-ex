defmodule Spacetraders.Bot.Trader do
  require Logger
  alias Spacetraders.API
  @behaviour :gen_statem

  defmodule State do
    alias Spacetraders.Bot.Trader.Planner.Market
    @enforce_keys [:trade_route, :ship, :cargo, :ship_location, :trade_item, :avail_funds]
    defstruct [:trade_route, :ship, :cargo, :ship_location, :trade_item, :avail_funds]

    @type t :: %State{
            trade_route: Market.trade_route(),
            ship: String.t(),
            cargo: list(any()),
            ship_location: String.t(),
            trade_item: String.t(),
            avail_funds: number()
          }
  end

  def callback_mode() do
    :state_functions
  end

  def terminate(reason, currentState, data) do
    Logger.error(msg: "Terminating state machine", reason: reason, state: currentState, data: data) 
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    trade_route = Keyword.fetch!(opts, :trade_route)
    ship = Keyword.fetch!(opts, :ship)
    funds = Keyword.get(opts, :funds, 50_000)

    {:ok, ship_data} = API.get_ship(ship)

    cargo = ship_data["cargo"]

    ship_location = ship_data["nav"]["waypointSymbol"]

    ship_nav = ship_data["nav"]

    trade_item = elem(trade_route, 0).trade["symbol"]

    Logger.info("Starting trading bot!")
    :gen_statem.start_link(
      __MODULE__,
      {trade_route, ship, cargo, ship_location, trade_item, funds, ship_nav},
      opts
    )
  end

  def init({trade_route, ship, cargo, ship_location, trade_item, funds, ship_nav}) do
    if ship_nav["status"] == "DOCKED" do
      {:ok, _} = API.orbit_ship(ship)
    end

    data = %State{
      trade_route: trade_route,
      ship: ship,
      cargo: cargo,
      ship_location: ship_location,
      trade_item: trade_item,
      avail_funds: funds
    }

    {:ok, :initial, data, {:next_event, :internal, :init}}
  end

  defp trade_item_amount(%State{} = data) do
    tmp =
      data.cargo["inventory"]
      |> Enum.find(&(&1["symbol"] == data.trade_item))

    if tmp != nil do
      tmp["units"]
    else
      0
    end
  end

  def initial(:internal, :init, %State{} = data) do
    if trade_item_amount(data) > 0 do
      {:next_state, :sell, data, [{:next_event, :internal, :start}]}
    else
      {:next_state, :buy, data, [{:next_event, :internal, :start}]}
    end
  end

  def sell(:internal, :start, %State{} = data) do
    Logger.info("sell start")
    sell_location = elem(data.trade_route, 1).symbol

    if data.ship_location != sell_location do
      {:ok, nav} = API.navigate_ship(data.ship, sell_location)

      cd = API.cooldown_ms(nav)

      {:keep_state, %{data | ship_location: sell_location}, [{:state_timeout, cd, :arrived}]}
    else
      {:keep_state_and_data, [{:next_event, :internal, :arrived}]}
    end
  end

  def sell(a, :arrived, %State{} = data) when a in [:internal, :state_timeout] do
    Logger.info("sell arrived")
    sell_location = elem(data.trade_route, 1).symbol
    true = sell_location == data.ship_location

    {:ok, _} = API.dock_ship(data.ship)
    {:ok, _} = API.refuel_ship(data.ship)

    data = do_sale(data)

    {:ok, _} = API.orbit_ship(data.ship)

    {:next_state, :buy, data, [{:next_event, :internal, :start}]}
  end

  defp get_market(%State{} = data, at) do
    symbol =
      case at do
        :buy -> elem(data.trade_route, 0).symbol
        :sell -> elem(data.trade_route, 1).symbol
      end

    {:ok, market_data} = API.get_market(symbol)

    Spacetraders.Market.enter_market_data(market_data)

    market_data
  end

  @spec trade_volume(map(), String.t()) :: number()
  defp trade_volume(market_data, symbol) do
    trade_good = market_data["tradeGoods"] |> Enum.find(&(&1["symbol"] == symbol))

    trade_good["tradeVolume"]
  end

  @spec buy_price(map(), String.t()) :: number()
  defp buy_price(market_data, symbol) do
    trade_good = market_data["tradeGoods"] |> Enum.find(&(&1["symbol"] == symbol))

    trade_good["purchasePrice"]
  end

  defp do_sale(%State{} = data) do
    market = get_market(data, :sell)

    volume = trade_volume(market, data.trade_item)
    to_sell = trade_item_amount(data)

    actual_sell = min(volume, to_sell)

    {:ok, sale} = API.sell_cargo(data.ship, data.trade_item, min(volume, to_sell))

    income = sale["transaction"]["totalPrice"]

    Logger.info("Sold #{actual_sell} units for #{income}.")

    data =
      struct!(data,
        cargo: sale["cargo"],
        avail_funds: data.avail_funds + income
      )

    if trade_item_amount(data) > 0 do
      data
    else
      do_sale(data)
    end
  end

  def buy(:internal, :start, %State{} = data) do
    Logger.info("buy start")
    buy_location = elem(data.trade_route, 0).symbol

    if data.ship_location != buy_location do
      {:ok, nav} = API.navigate_ship(data.ship, buy_location)

      cd = API.cooldown_ms(nav)

      {:keep_state, %{data | ship_location: buy_location}, [{:state_timeout, cd, :arrived}]}
    else
      {:keep_state_and_data, [{:next_event, :internal, :arrived}]}
    end
  end

  def buy(a, :arrived, %State{} = data) when a in [:internal, :state_timeout] do
    Logger.info("buy arrived")
    buy_location = elem(data.trade_route, 0).symbol
    true = data.ship_location == buy_location

    {:ok, _} = API.dock_ship(data.ship)
    {:ok, _} = API.refuel_ship(data.ship)

    data = do_buy(data)

    {:ok, _} = API.orbit_ship(data.ship)

    {:next_state, :sell, data, [{:next_event, :internal, :start}]}
  end

  @spec do_buy(%State{}) :: %State{}
  defp do_buy(%State{} = data) do
    market = get_market(data, :buy)

    trade_volume = trade_volume(market, data.trade_item)
    price = buy_price(market, data.trade_item)

    funds = data.avail_funds
    max_buy_funds = Integer.floor_div(funds, price)
    capacity = data.cargo["capacity"] - data.cargo["units"]

    actual_buy = min(min(max_buy_funds, capacity), trade_volume)

    updated_trade_route =
      Spacetraders.Bot.Trader.Planner.Market.update_trade_route(data.trade_route)

    data = struct!(data, trade_route: updated_trade_route)

    profit_per_unit = Spacetraders.Bot.Trader.Planner.get_profit_per_unit(updated_trade_route)

    if profit_per_unit < 500 do
      raise "Route no longer profitable"
    end

    if actual_buy > 0 do
      {:ok, purchase} = API.purchase_cargo(data.ship, data.trade_item, actual_buy)

      expense = purchase["transaction"]["totalPrice"]

      Logger.info("Bought #{actual_buy} units for #{expense}")

      data =
        struct!(data,
          cargo: purchase["cargo"],
          avail_funds: data.avail_funds - expense
        )

      do_buy(data)
    else
      data
    end
  end
end
