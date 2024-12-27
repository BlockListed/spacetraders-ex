defmodule Spacetraders.Bot.CheckMarket do
  alias Spacetraders.API
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [], opts)
  end

  def init([]) do
    children = [
      {DynamicSupervisor, name: Spacetraders.Bot.CheckMarket.SearchSupervisor},
      {Spacetraders.Bot.CheckMarket.Manager, name: Spacetraders.Bot.CheckMarket.Manager}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def add_check_ship(ship) do
    GenServer.cast(Spacetraders.Bot.CheckMarket.Manager, {:add_ship, ship})
  end

  def check_system(system) do
    GenServer.cast(Spacetraders.Bot.CheckMarket.Manager, {:check_system, system})
  end

  def register_all_probes() do
    {:ok, ships} = API.list_ships()

    ships
    |> Stream.filter(&(&1["frame"]["symbol"] == "FRAME_PROBE"))
    |> Stream.map(& &1["symbol"])
    |> Enum.each(&add_check_ship/1)
  end
end

defmodule Spacetraders.Bot.CheckMarket.Manager do
  alias Spacetraders.Bot.CheckMarket.RoutePlanner
  alias Spacetraders.API
  use GenServer

  defmodule State do
    defstruct ships: []
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init([]) do
    {:ok, %State{}}
  end

  def handle_cast({:add_ship, ship}, state) do
    state = %{state | ships: [ship | state.ships]}
    {:noreply, state}
  end

  def handle_cast({:check_system, system}, state) do
    {:ok, markets} = API.get_markets(system)
    markets = markets |> Enum.map(& &1["symbol"])

    avail_ships =
      state.ships
      |> Enum.filter(fn ship ->
        {:ok, ship_data} = API.get_ship(ship)
        ship_data["nav"]["route"]["destination"]["systemSymbol"] == system
      end)
      # take at max len(markets) ships
      |> Enum.take(Enum.count(markets))

    state = %{state | ships: state.ships -- avail_ships}

    routes = RoutePlanner.plan_random(avail_ships, markets)

    {:ok, _} =
      DynamicSupervisor.start_child(
        Spacetraders.Bot.CheckMarket.SearchSupervisor,
        {Spacetraders.Bot.CheckMarket.SearchManager, routes: routes}
      )

    {:noreply, state}
  end
end

defmodule Spacetraders.Bot.CheckMarket.SearchManager do
  alias Spacetraders.Market
  alias Spacetraders.Bot.CheckMarket.RoutePlanner.ShipRoute
  alias Spacetraders.Bot.CheckMarket
  alias Spacetraders.API
  require Logger

  defmodule Search do
    @enforce_keys [:task, :ship]
    defstruct [:task, :ship]

    @type t :: %Search{task: Task.t(), ship: String.t()}
  end

  def start_link(opts) do
    routes = Keyword.fetch!(opts, :routes)

    with {:ok, sup} <- Supervisor.start_link([], strategy: :one_for_all),
         {:ok, task_sup} <- Supervisor.start_child(sup, Task.Supervisor) do
      Supervisor.start_child(sup, {Task, fn -> do_search(task_sup, routes) end})
    else
      e -> e
    end
  end

  def child_spec(init_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_arg]},
      type: :supervisor
    }
  end

  def do_search(sup, routes) do
    Task.Supervisor.async_stream(sup, routes, &check_route/1, concurrency: 1024, ordered: false, timeout: :infinity)
    |> Enum.each(&Spacetraders.Bot.CheckMarket.add_check_ship/1)
  end

  def check_route(%ShipRoute{}=route) do
    {:ok, ship} = API.get_ship(route.ship)
    Process.sleep(API.cooldown_ms(ship))

    fly_route = fn waypoints ->
      Enum.each(waypoints, fn wp ->
        {:ok, nav} = API.navigate_ship(route.ship, wp)
        {:ok, market_data} = API.get_market(wp)
        Market.enter_market_data(market_data)

        Process.sleep(API.cooldown_ms(nav))
      end)
    end

    cond do
      Enum.fetch(route.waypoints, 0) == route.origin ->
        {:ok, market_data} = API.get_market(route.origin)
        Market.enter_market_data(market_data)
        [_ | waypoints] = route.waypoints
        fly_route.(waypoints)
      true ->
        fly_route.(route.waypoints)
    end

    route.ship
  end
end
