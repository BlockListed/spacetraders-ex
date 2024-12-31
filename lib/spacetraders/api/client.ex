defmodule Spacetraders.API.Client do
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.spacetraders.io/v2")
  plug(Tesla.Middleware.BearerAuth, token: Application.fetch_env!(:spacetraders, :token))
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Retry,
    delay: 500,
    max_retries: 10,
    max_delay: 4_000,
    should_retry: fn
      {:ok, %{status: status}} when status == 429 -> true
      _ -> false
    end
  )

  plug(Spacetraders.API.Ratelimit.Middleware, server: Spacetraders.API.Ratelimit)

  def agent() do
    get("/my/agent")
  end

  def list_ships(page \\ 1) do
    get("/my/ships", query: [limit: "20", page: to_string(page)])
  end

  def get_ship(ship) do
    get("/my/ships/#{ship}")
  end

  def list_systems(page \\ 1) do
    get("/systems", query: [limit: "20", page: to_string(page)])
  end

  def get_system(system) do
    get("/systems/#{system}")
  end

  def list_waypoints(system, page \\ 1) do
    get("/systems/#{system}/waypoints", query: [limit: "20", page: to_string(page)])
  end

  def get_markets(system, page \\ 1) do
    get("/systems/#{system}/waypoints",
      query: [limit: "20", page: to_string(page), traits: "MARKETPLACE"]
    )
  end

  def get_shipyards(system, page \\ 1) do
    get("/systems/#{system}/waypoints",
      query: [limit: "20", page: to_string(page), traits: "SHIPYARD"]
    )
  end

  def get_jump_gates(system, page \\ 1) do
    get("/systems/#{system}/waypoints",
      query: [limit: "20", page: to_string(page), type: "JUMP_GATE"])
  end

  def list_filtered_waypoints(system, traits, type, page \\ 1) do
    trait_query = Enum.map(traits, &{:traits, &1})
    type_query = case type do
      nil -> []
      type -> [type: type]
    end

    filter_query = type_query ++ trait_query

    get("/systems/#{system}/waypoints",
      query: filter_query ++ [limit: "20", page: to_string(page)])
  end

  def get_waypoint(waypoint) do
    get(waypoint_url(waypoint))
  end

  def get_market(waypoint) do
    get(waypoint_url(waypoint) <> "/market")
  end

  def get_shipyard(waypoint) do
    get(waypoint_url(waypoint) <> "/shipyard")
  end

  def get_jump_gate(waypoint) do
    get(waypoint_url(waypoint) <> "/jump-gate")
  end

  def orbit_ship(ship) do
    post("/my/ships/#{ship}/orbit", %{})
  end

  def dock_ship(ship) do
    post("/my/ships/#{ship}/dock", %{})
  end

  def navigate_ship(ship, waypoint) do
    post("/my/ships/#{ship}/navigate", %{
      waypointSymbol: waypoint
    })
  end

  def purchase_ship(shipyard, ship_type) do
    post("/my/ships", %{
      waypointSymbol: shipyard,
      shipType: ship_type
    })
  end

  def purchase_cargo(ship, symbol, units) do
    post("/my/ships/#{ship}/purchase", %{
      symbol: symbol,
      units: units
    })
  end

  def sell_cargo(ship, symbol, units) do
    post("/my/ships/#{ship}/sell", %{
      symbol: symbol,
      units: units
    })
  end

  def refuel_ship(ship, from_cargo) do
    post("/my/ships/#{ship}/refuel", %{
      fromCargo: from_cargo
    })
  end

  def create_survey(ship) do
    post("/my/ships/#{ship}/survey", %{})
  end

  def extract_resources(ship) do
    post("/my/ships/#{ship}/extract", %{})
  end

  def extract_resources_with_survey(ship, survey) do
    post("/my/ships/#{ship}/extract/survey", survey)
  end

  def siphon_resources(ship) do
    post("/my/ships/#{ship}/siphon", %{})
  end

  def jettison_cargo(ship, symbol, units) do
    post("/my/ships/#{ship}/jettison", %{
      symbol: symbol,
      units: units,
    })
  end

  def transfer_cargo(from_ship, to_ship, symbol, units) do
    post("/my/ships/#{from_ship}/transfer", %{
      tradeSymbol: symbol,
      units: units,
      shipSymbol: to_ship,
    })
  end

  def patch_nav(ship, flight_mode) do
    patch("/my/ships/#{ship}/nav", %{
      flightMode: flight_mode
    })
  end

  defp waypoint_url(waypoint) do
    system = Spacetraders.API.extract_system(waypoint)

    "/systems/#{system}/waypoints/#{waypoint}"
  end
end
