#!/bin/bash
echo Weather
echo
echo this can show multiple Zipcodes and it sounds a beep when a weather warning was issued.
echo
echo k to kill alarm
echo "(may not be as accurate and quick  as models from the National Weather Service, ONLY use 
echo this as a logging system or in a situation where it is the only thing available for weather updates)"
# Folders
ROOT="$HOME/.weather_alert"
ZIP_FILE="$ROOT/locations.txt"
LOG_DIR="$ROOT/logs"
mkdir -p "$ROOT" "$LOG_DIR"

# Log file
LOG="$LOG_DIR/weather_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG"

# Get forecast + zone from coords
get_zone_from_coords() {
    local LAT=$1
    local LON=$2
    local POINT_INFO=$(curl -s "https://api.weather.gov/points/$LAT,$LON")
    FORECAST_URL=$(echo "$POINT_INFO" | jq -r '.properties.forecast')
    ZONE_URL=$(echo "$POINT_INFO" | jq -r '.properties.forecastZone')
    CITY=$(echo "$POINT_INFO" | jq -r '.properties.relativeLocation.properties.city')
    STATE=$(echo "$POINT_INFO" | jq -r '.properties.relativeLocation.properties.state')
}

# Convert ZIP to coordinates
coords_from_zip() {
    local ZIP=$1
    local RESPONSE=$(curl -s "http://api.zippopotam.us/us/$ZIP")
    LAT=$(echo "$RESPONSE" | jq -r '.places[0].latitude')
    LON=$(echo "$RESPONSE" | jq -r '.places[0].longitude')
}

# Sound alarm with escape
alert_user() {
    echo -e "\n🔔 ALERT: $1"
    echo "Press 'q' to silence."

    while true; do
        espeak "$1 Alert! Stay safe!"
        echo -e "\a"
        read -t 2 -n 1 key
        [[ "$key" == "q" ]] && break
    done
}

# Add location (ZIP or coords)
add_location() {
    echo -n "Enter ZIP or lat,lon: "
    read LOC
    echo "$LOC" >> "$ZIP_FILE"
    echo "📍 Added: $LOC"
}

# Remove location
remove_location() {
    echo -n "Enter exact ZIP or lat,lon to remove: "
    read LOC
    sed -i "/^$LOC$/d" "$ZIP_FILE"
    echo "❌ Removed: $LOC"
}

# List saved
list_locations() {
    echo "📌 Saved locations:"
    cat "$ZIP_FILE"
}

# Parse weather for one location
check_weather_for() {
    local LOC=$1
    if [[ "$LOC" =~ ^[0-9]{5}$ ]]; then
        coords_from_zip "$LOC"
    else
        LAT=$(echo "$LOC" | cut -d',' -f1)
        LON=$(echo "$LOC" | cut -d',' -f2)
    fi

    get_zone_from_coords "$LAT" "$LON"
    ZONE_ID=$(basename "$ZONE_URL")

    echo -e "\n🌐 [$CITY, $STATE] ($LAT,$LON)" | tee -a "$LOG"
    echo "Forecast:" | tee -a "$LOG"
    curl -s "$FORECAST_URL" | jq -r '.properties.periods[0] | "\(.name): \(.detailedForecast)"' | tee -a "$LOG"

    echo -e "\n🌀 Alerts:" | tee -a "$LOG"
    ALERT_JSON=$(curl -s "https://api.weather.gov/alerts/active/zone/$ZONE_ID")
    ALERT_COUNT=$(echo "$ALERT_JSON" | jq '.features | length')

    if [[ "$ALERT_COUNT" -gt 0 ]]; then
        echo "$ALERT_JSON" | jq -r '.features[] | "🔺 \(.properties.event) | Severity: \(.properties.severity)\n\(.properties.description)\nInstructions: \(.properties.instruction // "None")\n"' | tee -a "$LOG"
        for TYPE in $(echo "$ALERT_JSON" | jq -r '.features[].properties.event'); do
            [[ "$TYPE" =~ (Tornado|Hurricane|Severe|Storm|Flood) ]] && alert_user "$TYPE in $CITY"
        done
    else
        echo "✅ No alerts." | tee -a "$LOG"
    fi

    # Extended weather info
    echo -e "\n📊 Detailed data:" | tee -a "$LOG"
    curl -s "$FORECAST_URL" | jq -r '.properties.periods[0] | "Wind: \(.windSpeed) \(.windDirection)\nTemp: \(.temperature)°\nPrecip Chance: \(.probabilityOfPrecipitation.value // "?" )%\nConditions: \(.shortForecast)\n"' | tee -a "$LOG"
}

# Monitor loop
monitor_loop() {
    while true; do
        echo -e "\n==== WEATHER UPDATE [$(date)] ====" | tee -a "$LOG"
        while IFS= read -r LOC; do
            check_weather_for "$LOC"
            echo "------------------------" | tee -a "$LOG"
        done < "$ZIP_FILE"
        echo -e "\n🔄 Refreshing in 60 seconds..."
        sleep 60
    done
}

# Main menu
while true; do
    echo -e "\n🌤️ Bash Weather Alert System"
    echo "1. Add location (ZIP or lat,lon)"
    echo "2. Remove location"
    echo "3. List saved locations"
    echo "4. Start monitoring"
    echo "5. Exit"
    echo -n "Choose: "
    read CHOICE

    case $CHOICE in
        1) add_location ;;
        2) remove_location ;;
        3) list_locations ;;
        4) monitor_loop ;;
        5) echo "🛑 Exiting."; exit ;;
        *) echo "❓ Invalid choice." ;;
    esac
done

