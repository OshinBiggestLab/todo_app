defmodule TodoAppWeb.TodoAppLive do
  use TodoAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, input: "")}
  end

  def handle_event("update_input", %{"user_input" => val}, socket) do
    IO.puts("User typed: #{val}")
    {:noreply, assign(socket, input: val)}
  end

  def render(assigns) do
    ~H"""
    <main class="w-full bg-blue_00 text-grey_11 flex flex-col justify-center items-center p-10">
    <div class="w-full max-w-[600px]">
      <header class="w-full flex justify-between">
        <h1>TODO</h1>
        <button>light btn</button>
      </header>
      <div>
      <section class="bg-desaturated_blue00 my-6 flex h-16 items-center gap-x-5 p-5 rounded-md">
       <div class=" w-7 h-7 border border-gb_0 rounded-full"></div>
        <input class="bg-desaturated_blue00 w-full h-full outline-hidden border-none" placeholder="Create a new todo..." type="text" name="user_input" value={@input} phx-change="update_input"/>
      </section>
      <section class="bg-desaturated_blue00 rounded-md">
        <ul>

        </ul>
        <div class="flex justify-between items-center p-5">
        <p> 5 <span>items left</span></p>
        <div>
        <button>All</button>
        <button>Active</button>
        <button>Completed</button>
        </div>
          <button>Clear completed</button>
       </div>
      </section>
      </div>
      </div>
    </main>
    """
  end
end
