defmodule Spacetraders.Bot.Trader.AutoTrader do
  require Logger
  use GenServer

  defmodule State do
    @enforce_keys [:ship, :system, :funds]
    defstruct [:ship, :system, :funds, pid: nil]
  end

  def start_link(opts) do
    ship = Keyword.fetch!(opts, :ship)
    system = Keyword.fetch!(opts, :system)
    funds = Keyword.get(opts, :funds, 50_000)

    GenServer.start_link(__MODULE__, {ship, system, funds}, opts)
  end

  def start_mining(%State{} = state) do
    {:ok, pid} = Spacetraders.Bot.Trader.Manager.do_trading(state.ship, state.system, state.funds)

    Process.monitor(pid)

    :ok = Spacetraders.Bot.CheckMarket.check_system("X1-UY62")

    %{state | pid: pid}
  end

  def init({ship, system, funds}) do
    state = %State{ship: ship, system: system, funds: funds}

    state = start_mining(state)

    {:ok, state}
  end

  def handle_info({:DOWN, _, :process, _, :normal}, state) do
    state = start_mining(state)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.info(msg: msg)

    {:noreply, state}
  end
end
