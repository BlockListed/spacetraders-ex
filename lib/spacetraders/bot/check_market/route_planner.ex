defmodule Spacetraders.Bot.CheckMarket.RoutePlanner do
  alias Spacetraders.API

  defmodule ShipRoute do
    @enforce_keys [:ship, :origin]
    defstruct [:ship, :origin, waypoints: []]

    @type t :: %ShipRoute{ship: String.t(), origin: String.t(), waypoints: [String.t()]}

    @spec from_ship(String.t()) :: t()
    def from_ship(ship) do
      {:ok, ship_data} = API.get_ship(ship)

      location = ship_data["nav"]["route"]["destination"]["symbol"]

      %ShipRoute{ship: ship, origin: location}
    end
  end

  def testing(func) do
    data = File.read!("test_data.json") |> Jason.decode!()

    ships = data["ships"]
    markets = data["markets"]

    routes = apply(Spacetraders.Bot.CheckMarket.RoutePlanner, func, [ships, markets])
    cost = route_cost(routes)

    {routes, cost}
  end

  @spec route_cost([ShipRoute.t()]) :: number()
  def route_cost(routes) do
    routes
    |> Stream.map(fn route ->
      Stream.concat([route.origin], route.waypoints)
      |> Stream.chunk_every(2, 1, :discard)
      |> Stream.map(fn [a, b] -> API.distance_between(a, b) end)
      |> Enum.sum()
    end)
    |> Enum.max()
  end

  def plan_random(ships, waypoints) do
    ships = Enum.map(ships, &ShipRoute.from_ship/1)

    1..256
    |> Task.async_stream(fn _ ->
      waypoints = Enum.shuffle(waypoints)

      routes = assign_naive(ships, waypoints)
      {routes, route_cost(routes)}
    end)
    |> Stream.map(fn {:ok, res} -> res end)
    |> Enum.min_by(&elem(&1, 1))
    |> elem(0)
  end

  @spec plan_route(ships :: [String.t()], waypoints :: [map()]) :: [ShipRoute.t()]
  def plan_route(ships, waypoints) do
    ships = Enum.map(ships, &ShipRoute.from_ship/1)

    assign_naive(ships, waypoints)
  end

  @spec assign_naive([ShipRoute.t()], [String.t()]) :: [ShipRoute.t()]
  defp assign_naive(ships, waypoints, ships_b \\ []) do
    case {waypoints, ships, ships_b} do
      {_, [], []} ->
        []

      {[wp | waypoints], [a | ships], _} ->
        new_ship = %{a | waypoints: [wp | a.waypoints]}
        assign_naive(ships, waypoints, [new_ship | ships_b])

      {waypoints, [], _} ->
        assign_naive(ships_b |> Enum.reverse(), waypoints, [])

      {[], _, _} ->
        Enum.reduce(ships_b, ships, fn ship, acc -> [ship | acc] end)
    end
  end

  @spec plan_shortest([String.t()], [map()]) :: [ShipRoute.t()]
  def plan_shortest(ships, waypoints) do
    ships = Enum.map(ships, &ShipRoute.from_ship/1)

    assign_shortest(ships, waypoints)
  end

  defp assign_shortest(ships, waypoints, ships_b \\ []) do
    cond do
      Enum.empty?(ships) && Enum.empty?(ships_b) ->
        []

      !Enum.empty?(waypoints) && !Enum.empty?(ships) ->
        [ship | ships] = ships

        curr_origin =
          case ship.waypoints do
            [wp | _] -> wp
            _ -> ship.origin
          end

        next_wp =
          Stream.map(waypoints, &{&1, API.distance_between(&1, curr_origin)})
          |> Enum.min_by(&elem(&1, 1))
          |> elem(0)

        waypoints = Enum.reject(waypoints, &(&1 == next_wp))

        ship = %{ship | waypoints: [next_wp | ship.waypoints]}

        assign_shortest(ships, waypoints, [ship | ships_b])

      Enum.empty?(ships) ->
        assign_shortest(ships_b |> Enum.reverse(), waypoints, [])

      Enum.empty?(waypoints) ->
        Enum.reduce(ships_b, ships, fn ship, acc -> [ship | acc] end)
    end
  end
end
