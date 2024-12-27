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

    :ok =
      File.write!(
        "test_data.json",
        Jason.encode_to_iodata!(%{markets: markets, ships: avail_ships})
      )

    state = %{state | ships: state.ships -- avail_ships}

    {:ok, _} =
      DynamicSupervisor.start_child(
        Spacetraders.Bot.CheckMarket.SearchSupervisor,
        {Spacetraders.Bot.CheckMarket.SearchManager, ships: avail_ships, markets: markets}
      )

    {:noreply, state}
  end
end

defmodule Spacetraders.Bot.CheckMarket.SearchManager do
  alias Spacetraders.Bot.CheckMarket
  alias Spacetraders.API
  require Logger

  defmodule Search do
    @enforce_keys [:task, :ship]
    defstruct [:task, :ship]

    @type t :: %Search{task: Task.t(), ship: String.t()}
  end

  def start_link(opts) do
    ships = Keyword.fetch!(opts, :ships)
    markets = Keyword.fetch!(opts, :markets) |> dbg

    with {:ok, sup} <- Supervisor.start_link([], strategy: :one_for_all),
         {:ok, task_sup} <- Supervisor.start_child(sup, Task.Supervisor) do
      Supervisor.start_child(sup, {Task, fn -> do_search(task_sup, ships, markets) end})
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

  @spec do_search(pid(), [String.t()], [String.t()], [Search.t()]) :: nil
  def do_search(sup, ships, markets, searches \\ []) do
    cond do
      !Enum.empty?(markets) && !Enum.empty?(ships) ->
        [ship_to_assign | ships] = ships

        ship_to_assign |> dbg

        {:ok, ship} = API.get_ship(ship_to_assign)

        ship_location = ship["nav"]["route"]["destination"]["symbol"] |> dbg

        if ship["nav"]["status"] == "DOCKED" do
          API.orbit_ship(ship_to_assign)
        end

        closest_market =
          markets
          |> Enum.map(&{&1, API.distance_between(ship_location, &1)})
          |> Enum.min_by(&elem(&1, 1))
          |> elem(0)

        markets = markets -- [closest_market]

        true = API.extract_system(ship_location) == API.extract_system(closest_market)

        task = Task.Supervisor.async(sup, fn -> check_market(ship, closest_market) end)

        new_search = %Search{task: task, ship: ship_to_assign}

        do_search(sup, ships, markets, [new_search | searches])

      !Enum.empty?(searches) ->
        completed =
          searches
          |> Enum.map(& &1.task)
          |> Task.yield_many(limit: 1, timeout: 10000)
          |> Enum.filter(&(elem(&1, 1) != nil))

        case completed do
          [{task, {:ok, market_data}}] ->
            Logger.info("Got market data", market_data: market_data)

            Spacetraders.Market.enter_market_data(market_data)

            %Search{ship: ship} = Enum.find(searches, &(&1.task == task))
            searches = Enum.filter(searches, &(&1.task != task))

            do_search(sup, [ship | ships], markets, searches)

          [] ->
            do_search(sup, ships, markets, searches)
        end

      Enum.empty?(markets) && Enum.empty?(searches) ->
        Enum.each(ships, &CheckMarket.add_check_ship/1)
        Logger.info("Completed search")
        nil
    end
  end

  def check_market(ship, market) do
    Process.sleep(API.cooldown_ms(ship))

    if ship["nav"]["route"]["destination"]["symbol"] != market do
      {:ok, nav} = API.navigate_ship(ship["symbol"], market) |> dbg

      Process.sleep(API.cooldown_ms(nav))
    end

    {:ok, market_data} = API.get_market(market)

    true = Map.has_key?(market_data, "tradeGoods")

    market_data
  end
end
