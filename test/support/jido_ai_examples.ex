defmodule Jido.Tools.Weather do
  use Jido.Action,
    name: "weather_summary",
    description: "Return a simple weather summary for coordinates",
    schema: [coordinates: [type: :string, required: true]]

  @impl true
  def run(%{coordinates: coordinates}, _context) do
    {:ok, %{coordinates: coordinates, summary: "Mild and clear"}}
  end
end

defmodule Jido.Tools.Weather.ByLocation do
  use Jido.Action,
    name: "weather_by_location",
    description: "Return a simple weather summary for a location",
    schema: [location: [type: :string, required: true]]

  @impl true
  def run(%{location: location}, _context) do
    {:ok, %{location: location, summary: "Mild and clear"}}
  end
end

defmodule Jido.Tools.Weather.Forecast do
  use Jido.Action,
    name: "weather_forecast",
    description: "Return a short forecast for coordinates",
    schema: [coordinates: [type: :string, required: true]]

  @impl true
  def run(%{coordinates: coordinates}, _context) do
    {:ok, %{coordinates: coordinates, forecast: "High 72F, low chance of rain"}}
  end
end

defmodule Jido.Tools.Weather.HourlyForecast do
  use Jido.Action,
    name: "weather_hourly_forecast",
    description: "Return a short hourly forecast for coordinates",
    schema: [coordinates: [type: :string, required: true]]

  @impl true
  def run(%{coordinates: coordinates}, _context) do
    {:ok, %{coordinates: coordinates, forecast: ["1pm sunny", "2pm breezy", "3pm clear"]}}
  end
end

defmodule Jido.Tools.Weather.CurrentConditions do
  use Jido.Action,
    name: "weather_current_conditions",
    description: "Return current weather conditions for coordinates",
    schema: [coordinates: [type: :string, required: true]]

  @impl true
  def run(%{coordinates: coordinates}, _context) do
    {:ok, %{coordinates: coordinates, temperature_f: 72, conditions: "Clear"}}
  end
end

defmodule Jido.Tools.Weather.Geocode do
  use Jido.Action,
    name: "weather_geocode",
    description: "Convert a location string to coordinates",
    schema: [location: [type: :string, required: true]]

  @impl true
  def run(%{location: location}, _context) do
    {:ok, %{location: location, coordinates: "41.8781,-87.6298"}}
  end
end

defmodule Jido.AI.Examples.CalculatorAgent do
  use Jido.AI.Agent,
    name: "calculator_agent",
    description: "A calculator agent that uses tools for arithmetic",
    tags: ["example", "demo", "math"],
    model: "anthropic:claude-haiku-4-5",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide
    ],
    system_prompt: """
    You are a helpful calculator assistant. Use tool calls for arithmetic operations.
    """,
    max_iterations: 6
end

defmodule Jido.AI.Examples.WeatherAgent do
  use Jido.AI.Agent,
    name: "weather_agent",
    description: "Weather assistant with travel and activity advice",
    tags: ["example", "demo", "weather"],
    model: "anthropic:claude-haiku-4-5",
    tools: [
      Jido.Tools.Weather,
      Jido.Tools.Weather.ByLocation,
      Jido.Tools.Weather.Forecast,
      Jido.Tools.Weather.HourlyForecast,
      Jido.Tools.Weather.CurrentConditions,
      Jido.Tools.Weather.Geocode
    ],
    system_prompt: """
    You are a helpful weather assistant. Convert locations to coordinates before
    using forecast tools and give practical advice.
    """,
    max_iterations: 6

  @default_timeout 30_000

  @spec get_forecast(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_forecast(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "Get the weather forecast for #{location}.",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end

  @spec get_conditions(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_conditions(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "What are the current conditions in #{location}?",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end

  @spec need_umbrella?(pid(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def need_umbrella?(pid, location, opts \\ []) do
    ask_sync(
      pid,
      "Should I bring an umbrella in #{location} today?",
      Keyword.put_new(opts, :timeout, @default_timeout)
    )
  end
end
