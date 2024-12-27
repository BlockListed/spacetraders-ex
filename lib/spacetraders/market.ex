defmodule Spacetraders.Market do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&init_table/0]}
    }
  end

  def init_table() do
    :ets.new(__MODULE__, [:set, :public, :named_table])

    Process.sleep(:infinity)
  end

  def enter_market_data(data) do
    :ets.insert(__MODULE__, [{data["symbol"], data}])
  end

  def get_all(acc \\ []) do
    case acc do
      [] ->
        case :ets.first_lookup(__MODULE__) do
          {_, [value]} -> get_all([value])
          :"$end_of_table" -> []
        end

      [value | _] ->
        case :ets.next_lookup(__MODULE__, elem(value, 0)) do
          {_, [next]} -> get_all([next | acc])
          :"$end_of_table" -> acc |> Enum.reverse()
        end
    end
  end

  def get_all_to_file(path) do
    all = get_all() |> Enum.map(&elem(&1, 1))

    File.write!(path, Jason.encode_to_iodata!(all))
  end
end
