defmodule Forecastr.Renderer.ASCII do
  @moduledoc """
  ASCII renderer
  Render weather ASCII art
  """

  import Forecastr.Renderer.Colours

  @relevant_times %{
    "09:00:00" => "Morning",
    "12:00:00" => "Noon",
    "18:00:00" => "Afternoon",
    "21:00:00" => "Evening",
    "00:00:00" => "Night"
  }

  @weekdays %{
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat",
    7 => "Sun"
  }

  @type weather :: map()
  @type output_type :: :ansi | :png | :ascii | :html
  @spec render(weather, output_type, units :: atom()) :: list()
  @doc "Render today weather condition or five days weather condition"
  def render(weather, output_type \\ :ascii, units)

  def render(
        %{
          "name" => name,
          "country" => country,
          "coordinates" => %{"lat" => lat, "lon" => lon},
          "temp" => temp,
          "temp_max" => temp_max,
          "temp_min" => temp_min,
          "id" => weather_id,
          "description" => main_weather_condition,
          "icon" => icon
        },
        output_type,
        units
      ) do
    bare_ascii =
      icon
      |> ascii_for(:ascii)
      |> String.split("\n")

    forecast =
      icon
      |> ascii_for(output_type)
      |> String.split("\n")
      |> append_reset_colours(output_type)
      |> append_weather_info(bare_ascii, main_weather_condition, temp, temp_max, temp_min, units)

    [
      ~s(Weather report: #{name}, #{country}\n),
      ~s(lat: #{lat}, lon: #{lon}\n),
      "\n",
      table([forecast], output_type)
    ]
  end

  # Fallback for weather data without icon field (backward compatibility)
  def render(
        %{
          "name" => name,
          "country" => country,
          "coordinates" => %{"lat" => lat, "lon" => lon},
          "temp" => temp,
          "temp_max" => temp_max,
          "temp_min" => temp_min,
          "id" => weather_id,
          "description" => main_weather_condition
        },
        output_type,
        units
      ) do
    # Fallback to unknown weather icon for legacy data without icon field
    bare_ascii =
      weather_id
      |> ascii_for(:ascii)
      |> String.split("\n")

    forecast =
      weather_id
      |> ascii_for(output_type)
      |> String.split("\n")
      |> append_reset_colours(output_type)
      |> append_weather_info(bare_ascii, main_weather_condition, temp, temp_max, temp_min, units)

    [
      ~s(Weather report: #{name}, #{country}\n),
      ~s(lat: #{lat}, lon: #{lon}\n),
      "\n",
      table([forecast], output_type)
    ]
  end

  def render(
        %{
          "name" => name,
          "country" => country,
          "coordinates" => %{"lat" => lat, "lon" => lon},
          "list" => forecast_list
        },
        output_type,
        units
      )
      when is_list(forecast_list) do
    forecasts =
      forecast_list
      |> extract_relevant_times()
      |> group_by_date()
      |> prepare_forecasts_for_rendering(output_type, units)

    # TODO: align correctly tabular output when we have different ASCII art
    # shapes
    [
      [
        ~s(Weather report: #{name}, #{country}\n),
        ~s(lat: #{lat}, lon: #{lon}\n),
        "\n"
      ]
      | [forecasts]
    ]
  end

  defp determine_max_length(ascii_list),
    do: ascii_list |> Stream.map(&String.length/1) |> Enum.max()

  def append_reset_colours(ascii_list, output_type),
    do:
      Enum.map(
        ascii_list,
        fn line ->
          case String.trim(line) do
            # Do not reset blank lines, we have no opening
            "" -> line
            _ -> line <> reset(output_type)
          end
        end
      )

  # TODO: re-organize weather info with humidity etc
  # We should pass a map as a parameter
  def append_weather_info(
        ascii_art_list,
        ascii_list,
        description,
        temperature,
        temp_max,
        temp_min,
        units
      ) do
    units = determine_unit(units)
    # The weather information to append to the ASCII art
    weather_info = [
      "#{description}     ",
      "#{temperature} #{units}  ",
      "max: #{temp_max} #{units}",
      "min: #{temp_min} #{units}"
    ]

    weather_length = Enum.count(weather_info)
    ascii_art_length = Enum.count(ascii_art_list)

    # Concatenate the ascii subset with the weather info
    ascii_with_weather_info =
      ascii_art_list
      |> concat_ascii_with_weather_info(ascii_list, weather_info)

    # Add the rest of the ascii art
    [ascii_with_weather_info | Enum.slice(ascii_art_list, weather_length..ascii_art_length)]
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec ascii_for(String.t() | atom(), atom()) :: String.t()
  # Handle standard weather icons (strings)
  def ascii_for(icon, output_type) when icon in ["clear-day", "clear-night"] do
    """
    #{bright_yellow(output_type)}  \\   /
    #{bright_yellow(output_type)}   .-.
    #{bright_yellow(output_type)}‒ (   ) ‒
    #{bright_yellow(output_type)}   `-᾿
    #{bright_yellow(output_type)}  /   \\
    """
  end

  def ascii_for(icon, output_type) when icon in ["partly-cloudy-day", "partly-cloudy-night"] do
    """
    #{yellow(output_type)}  \\  /
    #{yellow(output_type)}_ /\"\"#{reset(output_type)}#{white(output_type)}.-.
    #{yellow(output_type)}  \\#{reset(output_type)}#{white(output_type)}_(   ).
    #{yellow(output_type)}  /#{reset(output_type)}#{white(output_type)}(___(__)
    """
  end

  def ascii_for("cloudy", output_type) do
    """
    #{light_white(output_type)}    .--.
    #{light_white(output_type)} .-(    ).
    #{light_white(output_type)}(___.__)__)
    #{normal(output_type)}
    """
  end

  def ascii_for("overcast", output_type) do
    """
    #{white(output_type)}   .--.
    #{white(output_type)}.-(    ).
    #{white(output_type)}(___.__)__)
    #{normal(output_type)}
    """
  end

  def ascii_for(icon, output_type) when icon in ["fog", "fog-day", "fog-night"] do
    """
    #{light_white(output_type)}_ - _ - _ -
    #{light_white(output_type)}_ - _ - _
    #{light_white(output_type)}_ - _ - _ -
    #{light_white(output_type)}
    """
  end

  def ascii_for("extreme-fog", output_type) do
    """
    #{white(output_type)}▓▓▓▓▓▓▓▓▓
    #{white(output_type)}▓▓▓▓▓▓▓▓
    #{white(output_type)}▓▓▓▓▓▓▓▓▓
    #{white(output_type)}
    """
  end

  def ascii_for("mist", output_type) do
    """
    #{light_white(output_type)}_ _ _ _ _ _
    #{light_white(output_type)} _ _ _ _ _
    #{light_white(output_type)}_ _ _ _ _ _
    #{light_white(output_type)}
    """
  end

  def ascii_for(icon, output_type) when icon in ["haze-day", "haze-night"] do
    """
    #{light_white(output_type)}. . . . . .
    #{light_white(output_type)} . . . . .
    #{light_white(output_type)}. . . . . .
    #{light_white(output_type)}
    """
  end

  def ascii_for(icon, output_type) when icon in ["dust-day", "dust-night"] do
    """
    #{yellow(output_type)}≈ ≈ ≈ ≈ ≈ ≈
    #{yellow(output_type)} ≈ ≈ ≈ ≈ ≈
    #{yellow(output_type)}≈ ≈ ≈ ≈ ≈ ≈
    #{yellow(output_type)}
    """
  end

  def ascii_for(icon, output_type) when icon in ["overcast-day-smoke", "overcast-night-smoke"] do
    """
    #{white(output_type)}   .--.
    #{white(output_type)}.-(    ).
    #{white(output_type)}(___.__)__)
    #{light_white(output_type)}∼ ∼ ∼ ∼ ∼
    """
  end

  def ascii_for(icon, output_type) when icon in ["extreme-day-smoke", "extreme-night-smoke"] do
    """
    #{red(output_type)}   .--.
    #{red(output_type)}.-(    ).
    #{red(output_type)}(___.__)__)
    #{light_white(output_type)}∼∼ ∼∼ ∼∼
    """
  end

  def ascii_for("wind-alert", output_type) do
    """
    #{bright_yellow(output_type)}  ⚠
    #{white(output_type)}∼∼∼∼∼∼∼
    #{white(output_type)}∼∼∼∼∼∼
    #{white(output_type)}∼∼∼∼∼∼∼
    """
  end

  def ascii_for("tornado", output_type) do
    """
    #{white(output_type)}  .--.
    #{white(output_type)}.-(  ).
    #{white(output_type)} \\  /
    #{white(output_type)}  \\/
    #{white(output_type)}  /\\
    """
  end

  def ascii_for(icon, output_type)
      when icon in [
             "drizzle",
             "overcast-drizzle",
             "extreme-drizzle",
             "extreme-drizzle-fill",
             "rain"
           ] do
    """
    #{white(output_type)}   .-.
    #{white(output_type)}  (   ).
    #{white(output_type)}(___(__)
    #{blue(output_type)}  ʻ ʻ ʻ ʻ
    #{blue(output_type)}ʻ ʻ ʻ ʻ
    """
  end

  def ascii_for(icon, output_type)
      when icon in ["rain-fill", "partly-cloudy-day-rain", "partly-cloudy-night-rain"] do
    """
    #{yellow(output_type)}_`/\"\"#{reset(output_type)}#{white(output_type)}.-.
    #{yellow(output_type)} ,\\_#{reset(output_type)}(#{white(output_type)}   ).
    #{yellow(output_type)}  /#{reset(output_type)}#{white(output_type)}(___(__)
    #{blue(output_type)}   ʻ ʻ ʻ ʻ
    #{blue(output_type)}   ʻ ʻ ʻ ʻ
    """
  end

  def ascii_for(icon, output_type) when icon in ["extreme-rain", "extreme-rain-fill"] do
    """
    #{light_white(output_type)}     .-.
    #{light_white(output_type)}    (   ).
    #{light_white(output_type)}  (___(__)
    #{blue(output_type)}‚ʻ‚ʻ‚ʻ‚ʻ
    #{blue(output_type)}‚ʻ‚ʻ‚ʻ‚ʻ
    """
  end

  def ascii_for("overcast-rain", output_type) do
    """
    #{yellow(output_type)}_`/\"\"#{reset(output_type)}#{light_white(output_type)}.-.
    #{yellow(output_type)} ,\\#{reset(output_type)}#{light_white(output_type)}_(   ).
    #{yellow(output_type)} /#{reset(output_type)}#{light_white(output_type)}\(___(__)
    #{blue(output_type)}   ‚ʻ‚ʻ‚ʻ‚ʻ
    #{blue(output_type)}   ‚ʻ‚ʻ‚ʻ‚ʻ
    """
  end

  def ascii_for(icon, output_type) when icon in ["snow", "snow-fill", "snowflake"] do
    """
    #{white(output_type)}   .-.
    #{white(output_type)}  (   ).
    #{white(output_type)}(___(__)
    #{light_white(output_type)}  *  *  *
    #{light_white(output_type)}*  *  *
    """
  end

  def ascii_for("extreme-snow", output_type) do
    """
    #{white(output_type)}   .-.
    #{white(output_type)}  (   ).
    #{white(output_type)}  (___(__)
    #{light_white(output_type)}  * * * *
    #{light_white(output_type)}* * * *
    """
  end

  def ascii_for(icon, output_type)
      when icon in ["partly-cloudy-day-snow", "partly-cloudy-night-snow"] do
    """
    #{yellow(output_type)}_`/\"\"#{reset(output_type)}#{white(output_type)}.-.
    #{yellow(output_type)} ,\\_#{reset(output_type)}#{white(output_type)}\(   ).
    #{yellow(output_type)} /#{reset(output_type)}#{white(output_type)}(___(__)
    #{light_white(output_type)}   *  *  *
    #{light_white(output_type)}   *  *  *
    """
  end

  def ascii_for("overcast-snow", output_type) do
    """
    #{yellow(output_type)}_`/\"\"#{reset(output_type)}#{white(output_type)}.-.
    #{yellow(output_type)} ,\\_#{reset(output_type)}#{white(output_type)}(   ).
    #{yellow(output_type)}  /#{reset(output_type)}#{white(output_type)}(___(__)
    #{light_white(output_type)}      * * * *
    #{light_white(output_type)}    * * * *
    """
  end

  def ascii_for(icon, output_type) when icon in ["sleet", "sleet-fill"] do
    """
    #{white(output_type)}  .-.
    #{white(output_type)} (   ).
    #{white(output_type)}(___(__)
    #{blue(output_type)} ʻ#{reset(output_type)}#{light_white(output_type)} *#{reset(output_type)} ʻ #{light_white(output_type)}*
    #{light_white(output_type)}*#{reset(output_type)}#{blue(output_type)} ʻ#{reset(output_type)} *#{blue(output_type)} ʻ
    """
  end

  def ascii_for(icon, output_type)
      when icon in ["thunderstorms", "thunderstorms-night", "thunderstorms-overcast"] do
    """
    #{yellow(output_type)}_`/\"\"#{reset(output_type)}#{white(output_type)}.-.
    #{yellow(output_type)} ,\\#{reset(output_type)}#{white(output_type)}_(   ).
    #{yellow(output_type)} /#{reset(output_type)}#{white(output_type)}(___(__)
    #{bright_yellow(output_type)}  ⚡#{reset(output_type)}#{blue(output_type)}ʻ ʻ#{reset(output_type)}#{bright_yellow(output_type)}⚡ʻ
    #{blue(output_type)} ʻ ʻ ʻ ʻ
    """
  end

  def ascii_for("thunderstorms-extreme", output_type) do
    """
    #{white(output_type)}    .-.
    #{white(output_type)}   (   ).
    #{white(output_type)}  (___(__)
    #{blue(output_type)}‚ʻ#{reset(output_type)}#{bright_yellow(output_type)}⚡#{reset(output_type)}#{blue(output_type)}ʻ‚#{reset(output_type)}#{bright_yellow(output_type)}⚡#{reset(output_type)}#{blue(output_type)}‚ʻ
    #{blue(output_type)}‚ʻ‚ʻ#{reset(output_type)}#{bright_yellow(output_type)}⚡#{reset(output_type)}#{blue(output_type)}ʻ‚ʻ
    """
  end

  def ascii_for(icon, output_type) when icon in ["not-available"] or is_binary(icon) do
    """
    #{light_white(output_type)}.-.
    #{light_white(output_type)}__)
    #{light_white(output_type)}(
    #{light_white(output_type)}`-᾿
    #{light_white(output_type)}  •
    """
  end

  # Handle legacy ASCII codes (atoms) for backward compatibility only
  def ascii_for(:codeunknown, output_type) do
    """
    #{light_white(output_type)}.-.
    #{light_white(output_type)}__)
    #{light_white(output_type)}(
    #{light_white(output_type)}`-᾿
    #{light_white(output_type)}  •
    """
  end

  # Regex pattern defined as a function to comply with Erlang/OTP 28
  defp unicode_range, do: ~r/[\x{2600}-\x{9FFF}]/u

  defp concat_ascii_with_weather_info(ascii_art_list, ascii_list, weather_info) do
    blank_space = 1

    weather_length = Enum.count(weather_info)

    ascii_max_line_length = determine_max_length(ascii_list)
    ascii_art_subset = Enum.slice(ascii_art_list, 0..weather_length)
    ascii_subset = Enum.slice(ascii_list, 0..weather_length)

    Enum.map(Stream.zip([ascii_art_subset, weather_info, ascii_subset]), fn {ascii_art, weather,
                                                                             ascii} ->
      unicode_count =
        unicode_range()
        |> Regex.scan(ascii)
        |> List.flatten()
        |> Enum.count()

      ascii_length = String.length(ascii)
      to_pad = ascii_max_line_length - ascii_length - unicode_count + blank_space
      padding = String.duplicate(" ", to_pad)

      "#{ascii_art}#{padding}#{weather}"
    end)
  end

  defp prepare_forecasts_for_rendering(forecasts, output_type, units) do
    forecasts
    |> Enum.map(fn {date, forecasts} ->
      day =
        Map.get(
          @weekdays,
          date
          |> Date.from_iso8601!()
          |> Date.day_of_week()
        )

      forecasts =
        forecasts
        |> Enum.reduce([], fn %{
                                "dt_txt" => date_time,
                                "temp" => temp,
                                "temp_max" => temp_max,
                                "temp_min" => temp_min,
                                "description" => main_weather_condition,
                                "id" => weather_id
                              } = forecast_item,
                              acc ->
          # Use icon field if available, otherwise fall back to unknown
          icon_or_code =
            case Map.get(forecast_item, "icon") do
              nil -> :codeunknown
              icon -> icon
            end

          time = extract_time(date_time)
          period_of_the_day = Map.get(@relevant_times, time)

          bare_ascii =
            icon_or_code
            |> ascii_for(:ascii)
            |> String.split("\n")

          ascii =
            icon_or_code
            |> ascii_for(output_type)
            |> String.split("\n")
            |> append_reset_colours(output_type)
            |> append_weather_info(
              bare_ascii,
              main_weather_condition,
              temp,
              temp_max,
              temp_min,
              units
            )

          ["#{period_of_the_day} [#{time}]\n" <> ascii | acc]
        end)
        |> Enum.reverse()

      [table([[day, date]], output_type), table([forecasts], output_type)]
    end)
  end

  defp group_by_date(list) do
    Enum.group_by(list, fn element ->
      <<year::bytes-size(4)>> <>
        "-" <> <<month::bytes-size(2)>> <> "-" <> <<day::bytes-size(2)>> <> _rest =
        element["dt_txt"]

      year <> "-" <> month <> "-" <> day
    end)
  end

  defp extract_relevant_times(forecast_list) do
    forecast_list
    |> Stream.filter(fn element ->
      time = extract_time(element["dt_txt"])
      time in Map.keys(@relevant_times) == true
    end)
  end

  defp extract_time(date) do
    <<_year::bytes-size(4)>> <>
      "-" <> <<_month::bytes-size(2)>> <> "-" <> <<_day::bytes-size(2)>> <> " " <> time = date

    time
  end

  def table(data, :ascii), do: Elbat.table(data, :unicode)
  def table(data, :ansi), do: Elbat.table(data, :unicode)
  def table(data, :html), do: Elbat.table(data, :unicode)
  def table(data, _), do: data

  defp determine_unit(:metric), do: "°C"
  defp determine_unit(:imperial), do: "°F"
end
