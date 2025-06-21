defmodule TodoApp.TodoServer do
  use GenServer

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_) do
    initial_value = []
    dbg("start debgging")
    GenServer.start_link(__MODULE__, initial_value, name: :todos)
  end

  #  Client
  @spec todos() :: any()
  def todos do
    GenServer.call(:todos, :get_todos)
  end

  def add_todo(todo) when is_binary(todo) and todo != "" do
    GenServer.cast(:todos, {:add_todo, %{todo: todo, is_completed: false}})
    # GenServer.cast(:todos, {:add_todo, %{todo: todo, status: "incomplete"}})
  end

  # Server
  def init(initial_value) do
    {:ok, initial_value}
  end

  def handle_call(:get_todos, _from, todos) do
    {:reply, todos, todos}
  end

  def handle_cast({:add_todo, new_todo}, state) do
    {:noreply, [new_todo | state]}
  end
end
