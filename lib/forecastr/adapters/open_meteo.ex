defmodule Forecastr.OpenMeteo do
  @moduledoc false

  alias Forecastr.Geocoder

  @type when_to_forecast :: :today | :next_days
  @spec weather(when_to_forecast, String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def weather(when_to_forecast, query, opts) do
    endpoint = api_endpoint()

    with %{
           "lat" => lat,
           "lon" => lon,
           "address" => %{
             "city" => city,
             "country" => country
           }
         } <-
           query
           |> Geocoder.geocode()
           |> pick_location(),
         {:ok, forecast} <-
           fetch_weather_information(endpoint, lat, lon, when_to_forecast, convert_params(opts)) do
      {:ok,
       forecast
       |> add("name", city)
       |> add("country", country)
       |> add("when_to_forecast", Atom.to_string(when_to_forecast))}
    else
      {:error, e} ->
        {:error, e}

      other ->
        IO.warn(inspect(other))
        {:error, "Could not find location or forecast"}
    end
  end

  @spec normalize(map()) :: {:ok, map()}
  @doc """
  Normalize for today's weather or for the next days weather
  """
  def normalize(%{
        "when_to_forecast" => "today",
        "name" => name,
        "country" => country,
        "latitude" => lat,
        "longitude" => lon,
        "current" =>
          %{"temperature_2m" => temp, "apparent_temperature" => apparent_temperature} = weather
      }) do
    normalized =
      weather
      |> extract_main_weather()
      |> add("name", name)
      |> add("country", country)
      |> add("coordinates", %{"lat" => lat, "lon" => lon})
      |> add("temp", temp)
      |> add("temp_max", max(temp, apparent_temperature))
      |> add("temp_min", min(temp, apparent_temperature))

    {:ok, normalized}
  end

  def normalize(%{
        "when_to_forecast" => "next_days",
        "name" => name,
        "country" => country,
        "latitude" => lat,
        "longitude" => lon,
        "hourly" => %{
          "time" => times,
          "temperature_2m" => temperatures,
          "apparent_temperature" => apparent_temperature,
          "weather_code" => weather_codes
        }
      })
      when is_list(times) and is_list(temperatures) and is_list(weather_codes) do
    forecast_list =
      [times, temperatures, apparent_temperature, weather_codes]
      |> Enum.zip()
      |> Enum.map(&normalize_forecast_list/1)

    normalized =
      Map.new()
      |> add("name", name)
      |> add("country", country)
      |> add("coordinates", %{"lat" => lat, "lon" => lon})
      |> add("list", forecast_list)

    {:ok, normalized}
  end

  defp fetch_weather_information(endpoint, lat, lon, when_to_forecast, opts) do
    params = build_params(lat, lon, when_to_forecast, opts)

    case HTTPoison.get(endpoint, [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 400}} ->
        {:error, :not_found}

      error = {:error, _reason} ->
        error
    end
  end

  defp build_params(lat, lon, :today, opts) do
    base_params = %{
      latitude: lat,
      longitude: lon,
      # relative_humidity_2m,wind_speed_10m
      current: "temperature_2m,weather_code,apparent_temperature",
      forecast_days: 1
    }

    Map.merge(base_params, opts)
  end

  defp build_params(lat, lon, :next_days, opts) do
    base_params = %{
      latitude: lat,
      longitude: lon,
      hourly: "temperature_2m,weather_code,apparent_temperature",
      forecast_days: 7
    }

    Map.merge(base_params, opts)
  end

  defp extract_main_weather(%{"weather_code" => weather_code} = weather) do
    {description, icon} = weather_code_to_description_and_icon(weather_code)
    %{"description" => description, "id" => weather_code, "icon" => icon}
  end

  defp normalize_forecast_list({time, temperature, apparent_temperature, weather_code}) do
    {description, icon} = weather_code_to_description_and_icon(weather_code)

    # Parse ISO8601 datetime
    {:ok, datetime, _} = DateTime.from_iso8601(time)
    date = datetime |> DateTime.to_date() |> to_string()
    time_str = datetime |> DateTime.to_time() |> to_string()

    Map.new()
    |> add("temp", temperature)
    |> add("temp_max", max(temperature, apparent_temperature))
    |> add("temp_min", min(temperature, apparent_temperature))
    |> add("dt_txt", "#{date} #{time_str}")
    |> add("dt", DateTime.to_unix(datetime))
    |> add("description", description)
    |> add("id", weather_code)
    |> add("icon", icon)
  end

  defp weather_code_to_description_and_icon(0), do: {"Clear sky", "clear-day"}
  defp weather_code_to_description_and_icon(1), do: {"Mainly clear", "partly-cloudy-day"}
  defp weather_code_to_description_and_icon(2), do: {"Partly cloudy", "cloudy"}
  defp weather_code_to_description_and_icon(3), do: {"Overcast", "overcast"}
  defp weather_code_to_description_and_icon(45), do: {"Fog", "fog"}
  defp weather_code_to_description_and_icon(48), do: {"Depositing rime fog", "extreme-fog"}
  defp weather_code_to_description_and_icon(51), do: {"Light drizzle", "drizzle"}
  defp weather_code_to_description_and_icon(53), do: {"Moderate drizzle", "drizzle"}
  defp weather_code_to_description_and_icon(55), do: {"Dense drizzle", "overcast-drizzle"}
  defp weather_code_to_description_and_icon(56), do: {"Light freezing drizzle", "extreme-drizzle"}

  defp weather_code_to_description_and_icon(57),
    do: {"Dense freezing drizzle", "extreme-drizzle-fill"}

  defp weather_code_to_description_and_icon(61), do: {"Slight rain", "rain"}
  defp weather_code_to_description_and_icon(63), do: {"Moderate rain", "rain-fill"}
  defp weather_code_to_description_and_icon(65), do: {"Heavy rain", "extreme-rain"}
  defp weather_code_to_description_and_icon(66), do: {"Light freezing rain", "sleet"}
  defp weather_code_to_description_and_icon(67), do: {"Heavy freezing rain", "sleet-fill"}
  defp weather_code_to_description_and_icon(71), do: {"Slight snow fall", "snow"}
  defp weather_code_to_description_and_icon(73), do: {"Moderate snow fall", "snow-fill"}
  defp weather_code_to_description_and_icon(75), do: {"Heavy snow fall", "extreme-snow"}
  defp weather_code_to_description_and_icon(77), do: {"Snow grains", "snowflake"}

  defp weather_code_to_description_and_icon(80),
    do: {"Slight rain showers", "partly-cloudy-day-rain"}

  defp weather_code_to_description_and_icon(81), do: {"Moderate rain showers", "overcast-rain"}
  defp weather_code_to_description_and_icon(82), do: {"Violent rain showers", "extreme-rain-fill"}

  defp weather_code_to_description_and_icon(85),
    do: {"Slight snow showers", "partly-cloudy-day-snow"}

  defp weather_code_to_description_and_icon(86), do: {"Heavy snow showers", "overcast-snow"}
  defp weather_code_to_description_and_icon(95), do: {"Thunderstorm", "thunderstorms"}

  defp weather_code_to_description_and_icon(96),
    do: {"Thunderstorm with slight hail", "thunderstorms-overcast"}

  defp weather_code_to_description_and_icon(99),
    do: {"Thunderstorm with heavy hail", "thunderstorms-extreme"}

  defp weather_code_to_description_and_icon(_), do: {"Unknown weather condition", "not-available"}

  defp add(map, key, value) do
    map
    |> Map.put(key, value)
  end

  @spec api_endpoint() :: String.t()
  def api_endpoint(), do: "https://api.open-meteo.com/v1/forecast"

  defp convert_params(%{units: :imperial} = params) do
    params
    |> Map.put(:temperature_unit, "fahrenheit")
    |> Map.put(:wind_speed_unit, "mph")
    |> Map.put(:precipitation_unit, "inch")
    |> Map.delete(:units)
  end

  defp convert_params(%{units: _} = params), do: Map.delete(params, :units) |> convert_params()
  defp convert_params(%{} = params), do: params
  # default units
    |> Map.put(:temperature_unit, "celsius")
    |> Map.put(:wind_speed_unit, "kmh")
    |> Map.put(:precipitation_unit, "mm")

  defp convert_params(params) when is_list(params), do: Map.new(params) |> convert_params()

  defp pick_location(%{"address" => %{"city" => _city}} = body), do: body

  defp pick_location(%{"address" => %{"town" => town}} = body),
    do: put_in(body, ["address", "city"], town)

  defp pick_location(%{"address" => %{"village" => village}} = body),
    do: put_in(body, ["address", "city"], village)

  defp pick_location(%{"address" => %{"province" => province}} = body),
    do: put_in(body, ["address", "city"], province)

  defp pick_location(%{"address" => %{"suburb" => suburb}} = body),
    do: put_in(body, ["address", "city"], suburb)

  defp pick_location({"address", address}), do: %{"address" => address} |> pick_location()
  defp pick_location(other), do: other
end
