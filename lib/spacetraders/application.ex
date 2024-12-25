defmodule Spacetraders.Application do
  def start(_, _) do
    children = [
      {Finch, name: Spacetraders.Finch}
    ]

    IO.puts("Starting Spacetraders")

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
