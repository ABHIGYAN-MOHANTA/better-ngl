defmodule BetterNglWeb.RoomLive do
  use Phoenix.LiveView
  import Phoenix.Component
  alias Phoenix.PubSub

  @message_limit 100
  @inactive_timeout :timer.hours(24)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(60_000, :cleanup_old_messages)
    end

    # Generate a temporary ID that will be replaced if there's one in localStorage
    anonymous_id = "anon-#{MnemonicSlugs.generate_slug(3)}"

    {:ok,
     assign(socket,
       anonymous_id: anonymous_id,
       messages: [],
       online_users: MapSet.new(),
       typing_users: MapSet.new(),
       last_typing_reset: nil
     )}
  end

  defp format_timestamp(%DateTime{} = timestamp) do
    Calendar.strftime(timestamp, "%I:%M %p")
  end

  defp format_timestamp(_), do: "Invalid time"

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          assign(socket, :slug, nil)

        :show ->
          slug = params["slug"]

          if connected?(socket) do
            PubSub.subscribe(BetterNgl.PubSub, "room:#{slug}")

            PubSub.broadcast(
              BetterNgl.PubSub,
              "room:#{slug}",
              {:user_joined, socket.assigns.anonymous_id}
            )

            messages = get_room_messages(slug)

            assign(socket,
              slug: slug,
              messages: messages,
              online_users: MapSet.new([socket.assigns.anonymous_id])
            )
          else
            assign(socket, slug: slug)
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Only add the message if it's not already in our list
    if !Enum.any?(socket.assigns.messages, fn m -> m.id == message.id end) do
      updated_messages = Enum.take([message | socket.assigns.messages], @message_limit)
      {:noreply, assign(socket, messages: updated_messages)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:user_joined, user_id}, socket) do
    if user_id != socket.assigns.anonymous_id do
      PubSub.broadcast(
        BetterNgl.PubSub,
        "room:#{socket.assigns.slug}",
        {:user_presence, socket.assigns.anonymous_id}
      )

      socket =
        update(socket, :online_users, fn users ->
          MapSet.put(users, user_id)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:user_presence, user_id}, socket) do
    {:noreply, update(socket, :online_users, &MapSet.put(&1, user_id))}
  end

  @impl true
  def handle_info({:user_typing, user_id}, socket) do
    if user_id != socket.assigns.anonymous_id do
      socket = update(socket, :typing_users, &MapSet.put(&1, user_id))
      Process.send_after(self(), {:remove_typing, user_id}, 3000)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:remove_typing, user_id}, socket) do
    {:noreply, update(socket, :typing_users, &MapSet.delete(&1, user_id))}
  end

  @impl true
  def handle_info(:cleanup_old_messages, socket) do
    try do
      cutoff = DateTime.add(DateTime.utc_now(), -@inactive_timeout, :millisecond)

      # Convert messages to a list and delete manually if they're old
      messages = :ets.match_object(:chat_messages, {:_, %{room: socket.assigns.slug}})

      Enum.each(messages, fn {id, message} ->
        if DateTime.compare(message.timestamp, cutoff) == :lt do
          :ets.delete(:chat_messages, id)
        end
      end)

      {:noreply, socket}
    rescue
      # Ensure the LiveView doesn't crash if cleanup fails
      _ -> {:noreply, socket}
    end
  end

  # Add a new function to handle the user ID assignment
  def handle_event("restore_user_id", %{"userId" => user_id}, socket) do
    {:noreply, assign(socket, :anonymous_id, user_id)}
  end

  @impl true
  def handle_event("random-room", _params, socket) do
    random_slug = MnemonicSlugs.generate_slug(2)
    {:noreply, push_navigate(socket, to: "/room/#{random_slug}")}
  end

  @impl true
  def handle_event("typing", _params, socket) do
    now = System.system_time(:millisecond)
    last_reset = socket.assigns.last_typing_reset

    if is_nil(last_reset) || now - last_reset > 2000 do
      PubSub.broadcast(
        BetterNgl.PubSub,
        "room:#{socket.assigns.slug}",
        {:user_typing, socket.assigns.anonymous_id}
      )

      {:noreply, assign(socket, last_typing_reset: now)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    if String.trim(content) != "" do
      message = %{
        id: System.unique_integer([:positive, :monotonic]),
        room: socket.assigns.slug,
        content: content,
        sender_id: socket.assigns.anonymous_id,
        timestamp: DateTime.utc_now()
      }

      store_message(message)

      PubSub.broadcast(
        BetterNgl.PubSub,
        "room:#{socket.assigns.slug}",
        {:new_message, message}
      )

      # Remove the local message update since we'll receive it via broadcast
      {:noreply, update(socket, :typing_users, &MapSet.delete(&1, socket.assigns.anonymous_id))}
    else
      {:noreply, socket}
    end
  end

  defp store_message(message) do
    # Store as a tuple to preserve all fields
    :ets.insert(:chat_messages, {message.id, message})
  end

  defp get_room_messages(room) do
    :ets.match_object(:chat_messages, {:_, %{room: room}})
    |> Enum.map(fn {_id, message} -> message end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(@message_limit)
  end

  defp message_container_class(message, anonymous_id) do
    if message.sender_id == anonymous_id do
      "justify-end"
    else
      "justify-start"
    end
  end

  defp message_bubble_class(message, anonymous_id) do
    base_classes = "rounded-lg py-2 px-4 max-w-[80%]"

    if message.sender_id == anonymous_id do
      "#{base_classes} bg-blue-500 text-white"
    else
      "#{base_classes} bg-gray-100"
    end
  end

  defp timestamp_class(message, anonymous_id) do
    if message.sender_id == anonymous_id do
      "text-xs text-gray-500 text-right mr-2"
    else
      "text-xs text-gray-500 ml-2"
    end
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-4" id="chat-container" phx-hook="UserPersistence" data-anonymous-id={@anonymous_id}>
      <div class="flex justify-between items-center mb-4">
        <div>
          <h1 class="text-2xl font-bold">Better NGL</h1>
          <p class="text-lg">Room: <%= @slug %></p>
          <p class="text-sm text-gray-500">ID: <%= @anonymous_id %></p>
        </div>
        <div class="text-right">
          <p class="text-sm text-gray-600">
            <%= MapSet.size(@online_users) %> online
          </p>
          <%= if MapSet.size(@typing_users) > 0 do %>
            <p class="text-sm text-gray-500 italic">
              <%= if MapSet.size(@typing_users) == 1 do %>
                Someone is typing...
              <% else %>
                Multiple people are typing...
              <% end %>
            </p>
          <% end %>
        </div>
      </div>

      <div class="border rounded-lg shadow-sm bg-white">
        <div
          class="h-[500px] overflow-y-auto p-4 space-y-4"
          id="messages-container"
          phx-update="append"
        >
          <%= for message <- Enum.reverse(@messages) do %>
            <div class="flex flex-col space-y-1" id={"message-#{message.id}"}>
              <div class={"flex items-start gap-2.5 #{message_container_class(message, @anonymous_id)}"}>
                <div class={message_bubble_class(message, @anonymous_id)}>
                  <p class="text-xs mb-1 opacity-75">
                    <%= if message.sender_id == @anonymous_id do %>
                      You
                    <% else %>
                      <%= message.sender_id %>
                    <% end %>
                  </p>
                  <p class="text-sm"><%= message.content %></p>
                </div>
              </div>
              <span class={timestamp_class(message, @anonymous_id)}>
                <%= message.timestamp
                |> Timex.Timezone.convert("Asia/Kolkata")
                |> Timex.format!("{h12}:{m} {AM} IST") %>
              </span>
            </div>
          <% end %>
        </div>

        <div class="border-t p-4">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              placeholder="Type a message..."
              class="flex-1 rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
              required
              phx-keyup="typing"
            />
            <button
              type="submit"
              class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
            >
              Send
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen bg-gray-50">
      <div class="max-w-md w-full p-6 bg-white rounded-lg shadow-lg">
        <h1 class="text-2xl font-bold text-center mb-6">Welcome to Better NGL</h1>
        <button
          phx-click="random-room"
          class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg shadow-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        >
          Create a Random Room
        </button>
      </div>
    </div>
    """
  end
end
