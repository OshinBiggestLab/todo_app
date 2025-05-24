defmodule TodoAppWeb.TodoAppLive do
  use TodoAppWeb, :live_view

  @spec mount(any(), any(), any()) :: {:ok, any()}
  def mount(_params, _session, socket) do
    dbg("mount debgging")
    todos = GenServer.call(:todos, :get_todos)
    {:ok, assign(socket, input: "", todos: todos)}
  end

  # def handle_event("update_input", %{"user_input" => val}, socket) do
  #   # IO.puts("User typed: #{val}")
  #   {:noreply, assign(socket, input: val)}
  # end

  def handle_event("enter_pressed", %{"key" => "Enter", "value" => value }, socket) do
    TodoApp.TodoServer.add_todo(value)
    todos = TodoApp.TodoServer.todos()
    {:noreply, assign(socket, input: "", todos: todos)}
  end
  def handle_event("enter_pressed", _param, socket) do
    {:noreply, socket}
  end

  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <main class="font-josefinSans w-full bg-blue_00 text-grey_11 flex flex-col items-center p-10 min-h-screen">
    <div class="w-full max-w-[600px]">
      <header class="w-full flex justify-between">
        <h1>TODO</h1>
        <button>light btn</button>
      </header>
      <div>
      <section class="bg-desaturated_blue00 my-6 flex h-16 items-center gap-x-5 p-5 rounded-md">
       <div class="w-7 h-7 border border-gb_0 rounded-full"></div>
        <input class="bg-desaturated_blue00 text-light_grayish_blue text-lg w-full h-full border-none focus:outline-none focus:ring-0 focus:border-none" placeholder="Create a new todo..." type="text" name="user_input" value={@input}    phx-keydown="enter_pressed"/>
      </section>
      <section class="bg-desaturated_blue00 rounded-md">
        <ul>
        <%=  for todo <-@todos do %>
        <li class=" flex items-center border-b h-16 border-gb_001 p-5 gap-x-6">
        <%!-- todo.status === "completed" ? <div id="completed_todo"> :  <div id="incomplete_todo"> --%>
          <div class="completed_todo">
            <div class="bg-desaturated_blue00 rounded-full w-[26px] h-[26px]"></div>
          </div>
          <h1 class="text-light_grayish_blue text-lg"><%= todo.todo %></h1>
          <div class="ml-auto">X</div>
        </li>
        <% end %>
        </ul>
        <div class="text-gb_02 flex justify-between items-center p-5">
        <p class="text-sm"> <%= length(@todos) %>  <span>items left</span></p>
        <div class="flex gap-x-5 font-medium">
        <button class="hover:text-white">All</button>
        <button class="hover:text-white">Active</button>
        <button class="hover:text-white">Completed</button>
        </div>
          <button class="hover:text-white">Clear completed</button>
       </div>
      </section>
      </div>
      </div>
    </main>
    """
  end
end
