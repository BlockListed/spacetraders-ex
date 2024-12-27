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
      "waypointSymbol" => waypoint
    })
  end

  defp waypoint_url(waypoint) do
    system = extract_system(waypoint)

    "/systems/#{system}/waypoints/#{waypoint}"
  end

  def extract_system(waypoint) do
    [system_one, system_two, _] = String.split(waypoint, "-")

    Enum.join([system_one, system_two], "-")
  end
end
