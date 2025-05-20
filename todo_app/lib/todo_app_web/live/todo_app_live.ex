defmodule TodoAppWeb.TodoAppLive do
  use TodoAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <main>
      <h1>Todo App</h1>
    </main>
    """
  end
end
