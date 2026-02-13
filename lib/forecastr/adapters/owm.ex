defmodule Forecastr.OWM do
  @moduledoc false

  @type when_to_forecast :: :today | :next_days
  @spec weather(when_to_forecast, query :: String.t(), opts :: Keyword.t()) ::
          {:ok, map()} | {:error, atom()}
  def weather(when_to_forecast, query, opts) do
    endpoint = owm_api_endpoint(when_to_forecast)

    with %{
           "lat" => lat,
           "lon" => lon,
           "address" => %{
             "city" => city,
             "country" => country
           }
         } <- Forecastr.Geocoder.geocode(query),
         {:ok, body} <- fetch_weather_information(endpoint <> "?lat=#{lat}&lon=#{lon}", opts) do
      {:ok,
       body
       |> Map.put("name", city)
       |> Map.put("country", country)
       |> Map.put("when_to_forecast", Atom.to_string(when_to_forecast))}
    else
      {:error, _error} = error ->
        error

      %{} ->
        {:error, :place_not_found}
    end
  end

  @doc """
  Normalize for today's weather or for the next 5 days weather
  """
  @spec normalize(map()) :: {:ok, map()}
  def normalize(%{
        "name" => name,
        "sys" => %{"country" => country},
        "coord" => %{"lat" => lat, "lon" => lon},
        "weather" => weather,
        "main" => %{"temp" => temp, "temp_max" => temp_max, "temp_min" => temp_min} = main
      } = data) do
    normalized =
      weather
      |> extract_main_weather()
      |> add("name", name)
      |> add("country", country)
      |> add("coordinates", %{"lat" => lat, "lon" => lon})
      |> add("temp", temp)
      |> add("temp_max", temp_max)
      |> add("temp_min", temp_min)
      |> maybe_add("wind_speed", get_in(data, ["wind", "speed"]))
      |> maybe_add("wind_bearing", get_in(data, ["wind", "deg"]))
      |> maybe_add("humidity", main["humidity"])
      |> maybe_add("apparent_temp", main["feels_like"])

    {:ok, normalized}
  end

  def normalize(%{
        "city" => %{
          "name" => name,
          "country" => country,
          "coord" => %{"lat" => lat, "lon" => lon}
        },
        "list" => forecast_list
      })
      when is_list(forecast_list) do
    normalized =
      Map.new()
      |> add("name", name)
      |> add("country", country)
      |> add("coordinates", %{"lat" => lat, "lon" => lon})
      |> add("list", forecast_list |> Enum.map(&normalize_forecast_list/1))

    {:ok, normalized}
  end

  defp fetch_weather_information(endpoint, opts) do
    appid = opts[:appid] || Application.get_env(:forecastr, :appid)

    params =
      opts
      |> Keyword.take([:units])
      |> Enum.into(%{})
      |> Map.put_new(:units, :metric)
      |> Map.put(:APPID, appid)

    case HTTPoison.get("https://" <> endpoint, [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 400}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :api_key_invalid}

      {:error, _reason} = error ->
        error
    end
  end

  defp extract_main_weather(weather) do
    %{"description" => main_weather_condition, "id" => weather_id, "icon" => icon} =
      List.first(weather)

    standard_icon = owm_id_to_standard_icon(weather_id, icon)
    %{"description" => main_weather_condition, "id" => weather_id, "icon" => standard_icon}
  end

  # Map OWM weather IDs to standardized weather icons
  # Group 2xx: Thunderstorm
  defp owm_id_to_standard_icon(weather_id, _icon) when weather_id >= 200 and weather_id <= 232 do
    case weather_id do
      id when id in [200, 201, 210, 230, 231] -> "thunderstorms"
      id when id in [202, 211, 212, 221, 232] -> "thunderstorms-extreme"
      _ -> "thunderstorms"
    end
  end

  # Group 3xx: Drizzle
  defp owm_id_to_standard_icon(weather_id, _icon) when weather_id >= 300 and weather_id <= 321 do
    case weather_id do
      id when id in [300, 301, 310, 311, 321] -> "drizzle"
      id when id in [302, 312, 313, 314] -> "overcast-drizzle"
      _ -> "drizzle"
    end
  end

  # Group 5xx: Rain
  defp owm_id_to_standard_icon(weather_id, icon) when weather_id >= 500 and weather_id <= 531 do
    is_day = String.ends_with?(icon, "d")

    case weather_id do
      500 ->
        if is_day, do: "partly-cloudy-day-rain", else: "partly-cloudy-night-rain"

      501 ->
        "rain"

      id when id in [502, 503, 504] ->
        "extreme-rain"

      511 ->
        "sleet"

      id when id in [520, 521] ->
        if is_day, do: "partly-cloudy-day-rain", else: "partly-cloudy-night-rain"

      id when id in [522, 531] ->
        "overcast-rain"

      _ ->
        "rain"
    end
  end

  # Group 6xx: Snow
  defp owm_id_to_standard_icon(weather_id, icon) when weather_id >= 600 and weather_id <= 622 do
    is_day = String.ends_with?(icon, "d")

    case weather_id do
      id when id in [600, 601] ->
        "snow"

      602 ->
        "extreme-snow"

      id when id in [611, 612, 613] ->
        "sleet"

      id when id in [615, 616] ->
        "sleet"

      id when id in [620, 621] ->
        if is_day, do: "partly-cloudy-day-snow", else: "partly-cloudy-night-snow"

      622 ->
        "overcast-snow"

      _ ->
        "snow"
    end
  end

  # Group 7xx: Atmosphere
  defp owm_id_to_standard_icon(weather_id, icon) when weather_id >= 701 and weather_id <= 781 do
    is_day = String.ends_with?(icon, "d")

    case weather_id do
      # mist
      701 -> "mist"
      # smoke
      711 -> if is_day, do: "overcast-day-smoke", else: "overcast-night-smoke"
      # haze
      721 -> if is_day, do: "haze-day", else: "haze-night"
      # sand/dust whirls
      731 -> if is_day, do: "dust-day", else: "dust-night"
      # fog
      741 -> if is_day, do: "fog-day", else: "fog-night"
      # sand
      751 -> if is_day, do: "dust-day", else: "dust-night"
      # dust
      761 -> if is_day, do: "dust-day", else: "dust-night"
      # volcanic ash
      762 -> if is_day, do: "extreme-day-smoke", else: "extreme-night-smoke"
      # squalls
      771 -> "wind-alert"
      # tornado
      781 -> "tornado"
      _ -> "fog"
    end
  end

  # Group 800: Clear
  defp owm_id_to_standard_icon(800, icon) do
    if String.ends_with?(icon, "d"), do: "clear-day", else: "clear-night"
  end

  # Group 80x: Clouds
  defp owm_id_to_standard_icon(weather_id, icon) when weather_id >= 801 and weather_id <= 804 do
    is_day = String.ends_with?(icon, "d")

    case weather_id do
      # few clouds 11-25%
      801 -> if is_day, do: "partly-cloudy-day", else: "partly-cloudy-night"
      # scattered clouds 25-50%
      802 -> "cloudy"
      # broken/overcast clouds 51-100%
      id when id in [803, 804] -> "overcast"
      _ -> "cloudy"
    end
  end

  defp owm_id_to_standard_icon(_, _), do: "not-available"

  defp normalize_forecast_list(%{
         "weather" => weather,
         "main" => %{
           "temp" => temp,
           "temp_max" => temp_max,
           "temp_min" => temp_min
         },
         "dt_txt" => dt_txt,
         "dt" => dt
       }) do
    weather
    |> extract_main_weather()
    |> add("temp", temp)
    |> add("temp_max", temp_max)
    |> add("temp_min", temp_min)
    |> add("dt_txt", dt_txt)
    |> add("dt", dt)
  end

  defp add(map, key, value) do
    map
    |> Map.put(key, value)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  @spec owm_api_endpoint(when_to_forecast) :: String.t()
  def owm_api_endpoint(:today), do: "api.openweathermap.org/data/2.5/weather"
  def owm_api_endpoint(:next_days), do: "api.openweathermap.org/data/2.5/forecast"
end
