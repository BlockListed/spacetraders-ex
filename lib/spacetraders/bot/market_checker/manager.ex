defmodule Spacetraders.Bot.MarketChecker.Manager do
  alias Spacetraders.API
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [], opts)
  end

  def init(_init_arg) do
    children = [
      {Spacetraders.Bot.MarketChecker, name: Spacetraders.Bot.MarketChecker},
      {DynamicSupervisor, name: Spacetraders.Bot.MarketChecker.Probe},
      {Task, &start_probes/0}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def start_probes() do
    {:ok, ships} = API.list_ships()

    probes = Stream.filter(ships, &(&1["frame"]["symbol"] == "FRAME_PROBE"))

    probes
    |> Enum.each(fn ship ->
      {:ok, _} =
        DynamicSupervisor.start_child(
          Spacetraders.Bot.MarketChecker.Probe,
          {Spacetraders.Bot.MarketChecker.Probe,
           ship: ship["symbol"], server: Spacetraders.Bot.MarketChecker}
        )
    end)
  end
end
