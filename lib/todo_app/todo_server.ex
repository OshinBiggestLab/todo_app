defmodule TodoApp.TodoServer do
  use GenServer

  def start_link(_) do
    initial_value = 0
    GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
  end

end
