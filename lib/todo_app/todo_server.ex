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
   new_todo = %{
      id: System.unique_integer([:positive]),
      todo: todo,
      is_completed: false
  }
    GenServer.cast(:todos, {:add_todo, new_todo})
  end

  def toggle_completed(id) do
    GenServer.cast(:todos, {:toggle_completed, id})
  end

  def delete_todo(id) do
    GenServer.cast(:todos, {:delete_todo, id})
  end

  def delete_completed do
    GenServer.cast(:todos, :delete_completed)
  end


  # Server
  # Initializes the GenServer with an empty list of todos
  def init(initial_value) do
    {:ok, initial_value}
  end

  def handle_call(:get_todos, _from, todos) do
    {:reply, todos, todos}
  end

# Adds a new todo to the list
  def handle_cast({:add_todo, new_todo}, state) do
    {:noreply, [new_todo | state]}
  end

# Updates a todo by its ID
  def handle_cast({:toggle_completed, id}, state) do
  new_state =
    Enum.map(state, fn
      %{id: ^id} = todo -> %{todo | is_completed: !todo.is_completed}
      other -> other
    end)

  {:noreply, new_state}
end

# Deletes a todo by its ID
def handle_cast({:delete_todo, id}, state) do
  new_state = Enum.reject(state, fn todo -> todo.id == id end)
  {:noreply, new_state}
end

# Deletes all completed todos
def handle_cast(:delete_completed, state) do
  new_state = Enum.reject(state, fn todo -> todo.is_completed end)
  {:noreply, new_state}
end

end
