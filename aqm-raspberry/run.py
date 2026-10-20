import os
import sys
import time

import qwiic_bme280
import qwiic_ens160
import requests


READ_INTERVAL_SECONDS = 60
API_URL = os.getenv("API_URL", "")
DEVICE_API_KEY = os.getenv("DEVICE_API_KEY", "")


def main():
    if not API_URL:
        print("Set API_URL in aqm-raspberry/.env.", file=sys.stderr)
        return 1
    if not DEVICE_API_KEY:
        print("Set DEVICE_API_KEY in aqm-raspberry/.env.", file=sys.stderr)
        return 1

    try:
        print("Initializing SparkFun ENS160/BME280 Combo Board...")

        bme = qwiic_bme280.QwiicBme280()
        if not bme.connected:
            print("BME280 not detected. Check wiring and I2C.", file=sys.stderr)
            return 1

        if not bme.begin():
            print("BME280 initialization failed.", file=sys.stderr)
            return 1

        ens = qwiic_ens160.QwiicENS160()
        if not ens.is_connected():
            print("ENS160 not detected. Check wiring and I2C.", file=sys.stderr)
            return 1

        if not ens.begin():
            print("ENS160 initialization failed.", file=sys.stderr)
            return 1

        ens.set_operating_mode(ens.kOpModeStandard)
        print("Sensors ready! Press Ctrl+C to stop.\n")

        with requests.Session() as session:
            while True:
                try:
                    temp_c = bme.temperature_celsius
                    humidity = bme.humidity
                    pressure_hpa = bme.pressure / 100.0

                    ens.set_temp_compensation_celsius(temp_c)
                    ens.set_rh_compensation(humidity)

                    print("--- Environmental Data ---")
                    print(f"Temperature: {temp_c:.2f} C")
                    print(f"Humidity:    {humidity:.2f} %")
                    print(f"Pressure:    {pressure_hpa:.2f} hPa")

                    if ens.check_data_status():
                        aqi = ens.get_aqi()
                        tvoc = ens.get_tvoc()
                        eco2 = ens.get_eco2()
                        flags = ens.get_flags()

                        print("\n--- Air Quality Data ---")
                        print(f"AQI:         {aqi}")
                        print(f"TVOC:        {tvoc} ppb")
                        print(f"eCO2:        {eco2} ppm")
                        print(f"Sensor flags: {flags}")

                        payload = {
                            "aqi": aqi,
                            "tvoc": tvoc,
                            "eco2": eco2,
                            "temperature": temp_c,
                            "humidity": humidity,
                        }

                        try:
                            response = session.post(
                                API_URL,
                                json=payload,
                                headers={"X-Device-Key": DEVICE_API_KEY},
                                timeout=10,
                            )
                            response.raise_for_status()
                            print(f"Uploaded reading {response.json().get('id')}.")
                        except requests.RequestException as exc:
                            print(f"API request failed: {exc}", file=sys.stderr)
                    else:
                        print("\nENS160 data not ready; skipping upload.")

                    print("-" * 36 + "\n")
                except OSError as exc:
                    print(f"Sensor communication failed; will retry: {exc}", file=sys.stderr)
                finally:
                    time.sleep(READ_INTERVAL_SECONDS)

    except KeyboardInterrupt:
        print("\nProgram stopped by user.")
        return 0
    except OSError as exc:
        print(f"Unable to initialize sensors or open API session: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())


