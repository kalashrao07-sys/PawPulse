# PawPulse

> **An Intelligent IoT-Based Digital Healthcare Platform for Stray
> Dogs**

> **Status:** 🚧 In Development

------------------------------------------------------------------------

# Banner

> Replace with a banner image (`assets/banner.png`)

------------------------------------------------------------------------

## Overview

PawPulse is an IoT-enabled digital healthcare platform designed to
improve the health, welfare, and adoption opportunities of stray dogs.

Unlike conventional smart collars that mainly focus on GPS tracking,
PawPulse focuses on **preventive veterinary healthcare** by combining
wearable sensing, cloud computing, machine learning, and digital health
records.

The system enables NGOs, veterinarians, rescue organizations, and
caregivers to access a dog's complete health profile simply by scanning
a unique QR code attached to its collar.

------------------------------------------------------------------------

## Why PawPulse?

Millions of stray dogs receive medical care only after symptoms become
severe. Medical records are fragmented, treatment history is often
unavailable, and health conditions remain unnoticed.

PawPulse transforms this reactive process into a proactive healthcare
ecosystem.

------------------------------------------------------------------------

## Features

  -----------------------------------------------------------------------
  Category                            Features
  ----------------------------------- -----------------------------------
  Identity                            QR-based Digital Dog Profile

  Monitoring                          Heart Rate, Temperature, Activity

  Intelligence                        Activity Classification, Pulse
                                      Anomaly Detection, Hydration Risk
                                      Assessment, Overall Health
                                      Prediction

  Dashboard                           Live Graphs, Medical History,
                                      Alerts

  Cloud                               Supabase Database

  Alerts                              LED, Buzzer, Dashboard Notification
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## System Architecture

``` text
Smart Collar
      │
      ▼
ESP32 + Sensors
      │
      ▼
Supabase
      │
      ▼
ML Services
 ├── Activity Classification
 ├── Pulse Anomaly Detection
 ├── Hydration Risk Assessment
 └── Overall Health Prediction
      │
      ▼
Web Dashboard
```

------------------------------------------------------------------------

## Dashboard

### About the Dog

-   General Information
-   Medical History
-   Vaccination Records
-   Behaviour
-   Caregiver Information
-   Emergency Contacts

### Live Health Monitoring

-   Pulse
-   Temperature
-   Activity
-   Hydration Risk
-   Live Charts

### Overall Health

-   Healthy
-   Monitor
-   Warning
-   Critical

------------------------------------------------------------------------

## Machine Learning Pipeline

``` text
MPU6050 ─────────────► Activity Classification

Pulse Sensor ───────► Pulse Anomaly Detection

Pulse + Temperature + Activity
                    ─► Hydration Risk Assessment

Activity + Pulse + Temperature + Hydration
                    ─► Overall Health Prediction
```

------------------------------------------------------------------------

## Technology Stack

### Hardware

-   ESP32
-   Pulse Sensor
-   DS18B20
-   MPU6050
-   LED
-   Buzzer

### Software

-   HTML
-   CSS
-   JavaScript
-   Supabase
-   Chart.js

### AI

-   Random Forest
-   Isolation Forest
-   Gradient Boosting
-   Ordinal Logistic Regression

------------------------------------------------------------------------

## Repository Structure

``` text
PawPulse/
├── firmware/
├── web/
├── ml/
├── database/
├── docs/
├── assets/
└── README.md
```

------------------------------------------------------------------------

## Screenshots

Replace these placeholders:

-   assets/dashboard.png
-   assets/about-page.png
-   assets/health-page.png
-   assets/architecture.png

------------------------------------------------------------------------

## Roadmap

-   [x] System Architecture
-   [ ] ESP32 Firmware
-   [ ] Web Dashboard
-   [ ] Supabase Integration
-   [ ] ML Integration
-   [ ] Journal Submission

------------------------------------------------------------------------

## Research Scope

PawPulse demonstrates how IoT, cloud computing, and explainable machine
learning can be integrated into an affordable digital healthcare
ecosystem for stray dogs. The ML components assist caregivers by
providing activity recognition, pulse anomaly detection, hydration risk
estimation, and overall health assessment while maintaining transparent
and interpretable predictions.

------------------------------------------------------------------------

## License

MIT License

## Author

**Kalash Rao**
