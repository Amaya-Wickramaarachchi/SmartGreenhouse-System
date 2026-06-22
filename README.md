# SmartGreen - IoT & AI-Driven Greenhouse Management System 🌱

**SmartGreen** is a comprehensive IoT, Edge Computing, and AI-driven agricultural solution designed to automate greenhouse monitoring, optimize plant health, and provide real-time harvest readiness analysis. 

This repository contains the source code for the mobile application dashboard and the system integration logic developed as an undergraduate Final Year Project at Horizon Campus.

## 🚀 Key Features

* **Real-Time Telemetry Dashboard:** Monitors live environmental data including Temperature, Humidity, Soil Moisture, and Light Intensity (Lux) using a sleek Flutter UI.
* **AI Harvest Analysis (Edge Vision):** Utilizes a YOLOv8 object detection model at the edge to scan fruits, count the ready-to-harvest yield, and send automated real-time alerts to the app.
* **Plant Disease Diagnosis:** Integrates a Convolutional Neural Network (CNN) trained on custom and PlantVillage datasets to accurately identify leaf diseases with a ~91.8% validation accuracy.
* **Automated Environment Control:** Triggers water and climate control systems based on predefined targets stored in Firebase.
* **Secure Real-Time Communication:** Uses MQTT over TLS (Port 8883) via HiveMQ to securely bridge the Edge AI devices, IoT sensors, and the mobile application with zero latency.

## 🛠️ Technology Stack

**Mobile Application:**
* Framework: Flutter (Dart)
* State Management & Logic: Provider / BLoC
* UI/UX: Modern Minimalist, Glassmorphism elements

**IoT & Hardware Layer:**
* Microcontroller: ESP32 (Wi-Fi enabled)
* Sensors: DHT22 (Temp/Humidity), BH1750 (Light), Analog Soil Moisture Sensor

**Edge Computing & Artificial Intelligence:**
* Object Detection: YOLOv8 (Achieved 84.3% mAP50 for fruit maturity detection)
* Disease Classification: Custom CNN architecture
* Edge Scripting: Python, OpenCV

**Cloud & Backend Integration:**
* Message Broker: HiveMQ (MQTT Protocol)
* Database: Firebase Cloud Firestore (For target configuration)

## 📸 System Architecture & Data Flow

1. **Capture & Infer:** The Edge Device captures images and runs the YOLOv8/CNN models locally.
2. **Transmit:** The results (harvest count, status) and telemetry data are published as JSON payloads to `greenhouse/fruit_result` and `greenhouse/telemetry` MQTT topics.
3. **Display:** The Flutter mobile application subscribes to these topics and dynamically updates the UI cards without requiring manual page refreshes.

## 🧑‍💻 Developer
**Amaya Wickramaarachchi** BSc (Hons) in Information Technology (Networking and Mobile Computing)  
Horizon Campus, Sri Lanka
