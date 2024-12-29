defmodule Spacetraders.Bot.MarketChecker.Probe do
  require Logger
  alias Spacetraders.Market
  alias Spacetraders.Bot.MarketChecker
  alias Spacetraders.API
  @behaviour :gen_statem

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    ship = Keyword.fetch!(opts, :ship)
    server = Keyword.fetch!(opts, :market_checker)

    name = :"Spacetraders.Bot.MarketChecker.Probe.#{ship}"

    :gen_statem.start_link({:local, name}, __MODULE__, {ship, server}, opts)
  end

  def init({ship, server}) do
    Logger.info("Starting probe #{server}!")

    {:ok, ship_data} = API.get_ship(ship)

    location = ship_data["nav"]["waypointSymbol"]

    case ship_data["nav"]["status"] do
      "IN_ORBIT" ->
        {:ok, :running, {ship, location, server}, [{:next_event, :internal, :run}]}

      "DOCKED" ->
        {:ok, _} = API.orbit_ship(ship)
        {:ok, :running, {ship, location, server}, [{:next_event, :internal, :run}]}

      "IN_TRANSIT" ->
        cd = API.cooldown_ms(ship_data)
        {:ok, :running, {ship, location, server}, [{:timeout, cd, :run}]}
    end
  end

  def callback_mode() do
    :state_functions
  end

  def terminate(reason, currentState, data) do
    Logger.warning(
      msg: "Terminating state machine",
      reason: reason,
      state: currentState,
      data: data
    )
  end

  def running(a, :run, {ship, location, server}) when a in [:internal, :timeout] do
    to_check = MarketChecker.get_market(server, location)

    if location != to_check do
      Logger.info("Moving #{ship} to #{to_check}")
      {:ok, nav} = API.navigate_ship(ship, to_check)
      cd = API.cooldown_ms(nav)

      Process.sleep(cd)
    else
      Logger.info("#{ship} not moving")
    end

    Market.update_market_data(to_check)

    {:keep_state_and_data, [{:next_event, :internal, :run}]}
  end
end
