import paho.mqtt.client as mqtt
import json

# Broker Connection Details
broker = "c0eacb6e24dd4984814b3e19f4daa7a4.s1.eu.hivemq.cloud"
port = 8883
username = "greenhouse_admin"
password = "Admin@123"

# Setup TLS/SSL Client
# Using CallbackAPIVersion.VERSION2 for compatibility with newer paho-mqtt versions
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.tls_set() 
client.username_pw_set(username, password)

print("Connecting to HiveMQ...")
client.connect(broker, port)

# ==========================================
# TEST 1: Simulate Sensor Data (Telemetry)
# ==========================================
sensor_topic = "greenhouse/sensor_data"

sensor_payload = {
    "temperature": 29.5,
    "humidity": 68.2,
    "soil_moisture": 45.0,
    "light": 650.0,
    "timestamp": "2026-06-22 13:00:00"
}

print(f"\nPublishing to {sensor_topic}...")
client.publish(sensor_topic, json.dumps(sensor_payload))
print("Sensor data sent successfully!")

# ==========================================
# TEST 2: Simulate AI Harvest Result
# ==========================================
harvest_topic = "greenhouse/fruit_result"

harvest_payload = {
    "analysis_type": "fruit",
    "total_fruits": 8,
    "harvest_status": "Ready to Harvest",
    "timestamp": "2026-06-22 13:00:05"
}

print(f"\nPublishing to {harvest_topic}...")
client.publish(harvest_topic, json.dumps(harvest_payload))
print("Harvest data sent successfully!")

client.disconnect()
print("\nTest complete. Check your Flutter App!")