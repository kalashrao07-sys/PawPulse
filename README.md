# 🐕 PawPulse — Smart Health Monitoring Collar for Stray Dogs

## 📌 Overview

**PawPulse** is an IoT-based Smart Health Monitoring Collar designed for stray dogs to improve their healthcare, safety, and chances of adoption. The system enables NGOs, veterinarians, and caregivers to monitor vital health parameters of stray dogs using an ESP32-powered smart collar and a web-based dashboard.

Each dog is assigned a unique QR code attached to its collar. Scanning the QR code opens the dog's dedicated health profile webpage containing general details, medical records, and live health monitoring features.

The project focuses on providing an affordable, scalable, and power-efficient veterinary monitoring solution using IoT and web technologies.

---

# 🚀 Features

## 🐶 Dog Profile Management

Each stray dog has a unique digital profile containing:

* General Information
* Medical History
* Behavioral Traits
* Caregiver & Community Details
* Emergency Information

Accessible instantly through QR code scanning.

---

# ❤️ Live Health Monitoring

## 1️⃣ Heart Rate Monitoring

* Real-time BPM monitoring using pulse sensor
* Live pulse display
* Basic pulse graph visualization
* Abnormal heart rate detection

---

## 2️⃣ Body Temperature Monitoring

* Temperature monitoring using DS18B20 sensor
* Fever and overheating detection
* Live temperature display

---

## 3️⃣ Activity Monitoring

* Background motion monitoring using MPU6050
* Detects:

  * Long inactivity
  * Sudden motion spikes
  * General activity status

Low-power mode during nighttime to conserve battery.

---

## 4️⃣ Hydration Status Detection

On-demand hydration analysis based on:

* Activity levels
* Temperature
* Pulse data

Possible outputs:

* Hydrated
* Needs Water
* Dehydration Risk

---

## 5️⃣ Final Health Status Engine

Combines multiple health parameters and provides:

* 🟢 Healthy
* 🟡 Monitor
* 🟠 Warning
* 🔴 Critical

Helps NGOs and veterinarians quickly assess the dog’s overall condition.

---

# 🌐 Web Dashboard

The system includes a responsive web dashboard built using:

* HTML
* CSS
* JavaScript

The dashboard provides:

* Dog information
* Real-time sensor data
* Health status indicators
* Live monitoring controls
* Emergency alerts

---

# ⚙️ Tech Stack

## Hardware

* ESP32
* Pulse Sensor
* DS18B20 Temperature Sensor
* MPU6050 Accelerometer
* LED Indicators
* Buzzer

---

## Software & Cloud

* HTML
* CSS
* JavaScript
* Supabase
* Chart.js

---

# 🧩 System Architecture

```text
ESP32 → Supabase → Web Dashboard
          ↑
      QR-based Dog Profile Access
```

---

# 🔋 Power Optimization

The system is designed with power efficiency in mind:

* Sensors operate on-demand where possible
* Activity monitoring runs in lightweight background mode
* Reduced monitoring sensitivity during nighttime

---

# 🚨 Emergency Alert System

If abnormal health conditions are detected:

* Buzzer activates
* LED flashes
* Dashboard warning is triggered

Examples:

* High/low heart rate
* High body temperature
* Extreme inactivity
* Dehydration risk

---

# 📊 Database Structure (Simplified)

```text
dogs/
   DOG001/
      about/
      liveData/
      alerts/
      activity/
```

---

# 🎯 Project Goals

* Improve stray dog healthcare
* Support NGOs and veterinarians
* Enable quick access to medical details
* Increase adoption chances
* Build a low-cost scalable monitoring solution

---

# 🛠️ Future Improvements

* Breathing pattern monitoring
* AI-based anomaly detection
* Adoption request system
* Multi-dog analytics dashboard
* Mobile application support

---

# 📷 QR-Based Access

Each collar includes a unique QR code.

Scanning the QR code:

* Opens the dog’s health profile
* Displays live health information
* Allows monitoring and status checking

---

# 🏆 Use Cases

* Animal welfare NGOs
* Veterinary healthcare
* Stray dog monitoring
* Rescue operations
* Community animal care systems

---

# 👨‍💻 Developed By Kalash Rao

Developed as an IoT + Web-based healthcare innovation project focused on improving the welfare and healthcare accessibility of stray dogs using smart wearable technology.
