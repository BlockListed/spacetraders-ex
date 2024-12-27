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

  @spec plan_random([String.t()], [map()]) :: [ShipRoute.t()]
  def plan_random(ships, waypoints) do
    ships = Enum.map(ships, &ShipRoute.from_ship/1)

    # yes, this is the best I could think of.
    # atleast it's multithreaded.
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
end
