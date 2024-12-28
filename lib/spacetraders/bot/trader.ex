defmodule Spacetraders.Bot.Trader do
  require Logger
  alias Spacetraders.Bot.Trader.Planner.Market.TradeRoute
  alias Spacetraders.API
  @behaviour :gen_statem

  defmodule State do
    alias Spacetraders.Bot.Trader.Planner.Market.TradeRoute
    @enforce_keys [:trade_route, :ship, :cargo, :ship_location, :avail_funds]
    defstruct [:trade_route, :ship, :cargo, :ship_location, :avail_funds]

    @type t :: %State{
            trade_route: TradeRoute.t(),
            ship: String.t(),
            cargo: list(any()),
            ship_location: String.t(),
            avail_funds: number()
          }
  end

  def callback_mode() do
    :state_functions
  end

  def terminate(reason, currentState, data) do
    Logger.error(
      msg: "Terminating state machine",
      reason: reason,
      state: currentState,
      data: data
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
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

    Logger.info("Starting trading bot!")

    :gen_statem.start_link(
      __MODULE__,
      {trade_route, ship, cargo, ship_location, funds, ship_nav},
      opts
    )
  end

  def init({trade_route, ship, cargo, ship_location, funds, ship_nav}) do
    if ship_nav["status"] == "DOCKED" do
      {:ok, _} = API.orbit_ship(ship)
    end

    data = %State{
      trade_route: trade_route,
      ship: ship,
      cargo: cargo,
      ship_location: ship_location,
      avail_funds: funds
    }

    if ship_nav["status"] == "IN_TRANSIT" do
      # TODO: make this api not stupid
      cd = API.cooldown_ms(%{"nav" => ship_nav})
      {:ok, :waiting, data, {:state_timeout, cd, :arrived}}
    else
      {:ok, :initial, data, {:next_event, :internal, :init}}
    end
  end

  defp trade_item_amount(%State{} = data) do
    tmp =
      data.cargo["inventory"]
      |> Enum.find(&(&1["symbol"] == data.trade_route.symbol))

    if tmp != nil do
      tmp["units"]
    else
      0
    end
  end

  def waiting(:state_timeout, :arrived, %State{} = data) do
    {:next_state, :initial, data, [{:next_event, :internal, :init}]}
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
    sell_location = data.trade_route.to

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
    sell_location = data.trade_route.to
    true = sell_location == data.ship_location

    {:ok, _} = API.dock_ship(data.ship)
    {:ok, _} = API.refuel_ship(data.ship)
    :ok = Spacetraders.Market.update_market_data(data.trade_route.to)

    data = do_sale(data)

    {:ok, _} = API.orbit_ship(data.ship)

    if TradeRoute.profit(data.trade_route) >= 500 do
      {:next_state, :buy, data, [{:next_event, :internal, :start}]}
    else
      Logger.info("Stopping trade route, since it's no longer profitable!")
      :stop
    end
  end

  defp do_sale(%State{} = data) do
    volume = TradeRoute.sell_volume(data.trade_route)
    to_sell = trade_item_amount(data)

    actual_sell = min(volume, to_sell)

    if actual_sell > 0 do
      {:ok, sale} = API.sell_cargo(data.ship, data.trade_route.symbol, min(volume, to_sell))

      income = sale["transaction"]["totalPrice"]

      Logger.info("Sold #{actual_sell} units for #{income}.")

      data =
        struct!(data,
          cargo: sale["cargo"],
          avail_funds: data.avail_funds + income
        )

      do_sale(data)
    else
      data
    end
  end

  def buy(:internal, :start, %State{} = data) do
    Logger.info("buy start")
    buy_location = data.trade_route.from

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
    buy_location = data.trade_route.from
    true = data.ship_location == buy_location

    {:ok, _} = API.dock_ship(data.ship)
    {:ok, _} = API.refuel_ship(data.ship)
    :ok = Spacetraders.Market.update_market_data(data.trade_route.from)

    data = do_buy(data)

    {:ok, _} = API.orbit_ship(data.ship)

    {:next_state, :sell, data, [{:next_event, :internal, :start}]}
  end

  @spec do_buy(State.t()) :: State.t()
  defp do_buy(%State{}=data) do
    trade_volume = TradeRoute.buy_volume(data.trade_route)
    price = TradeRoute.buy_price(data.trade_route)

    funds = data.avail_funds
    max_buy_funds = Integer.floor_div(funds, price)
    capacity = data.cargo["capacity"] - data.cargo["units"]

    actual_buy = min(min(max_buy_funds, capacity), trade_volume)

    profit_per_unit = TradeRoute.profit(data.trade_route)

    Logger.info("Trading with an expected profit of #{profit_per_unit}!")

    if actual_buy > 0 && profit_per_unit >= 500 do
      {:ok, purchase} = API.purchase_cargo(data.ship, data.trade_route.symbol, actual_buy)
      :ok = Spacetraders.Market.update_market_data(data.trade_route.from)

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
