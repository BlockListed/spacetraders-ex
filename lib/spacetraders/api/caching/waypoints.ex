defmodule Spacetraders.API.Caching.Waypoints do
  def init_table do
    Task.start_link(fn ->
      :dets.open_file(__MODULE__, file: ~c"waypoint_cache.dets", type: :set)
      Process.sleep(:infinity)
    end)
  end

  def get_waypoint(waypoint) do
    case :dets.lookup(__MODULE__, waypoint) do
      [waypoint_info] -> {:some, waypoint_info}
      _ -> :none
    end
  end

  def populate_waypoint(waypoint, waypoint_info) do
    :dets.insert(__MODULE__, [{waypoint, waypoint_info}])
  end
end
