# NAPS SUNMI P2 Studio & Test Workbench

A fintech workbench and reference Flutter implementation for integrating **NAPS Morocco** electronic payment terminals (**SUNMI P2**) using the bidirectional **M2M TLV Protocol** over **TCP/IP** and **Serial USB-C**.

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Modular Layout](#architecture--modular-layout)
- [Workbench Features](#workbench-features)
  - [1. Transaction Desk (Payment)](#1-transaction-desk-payment)
  - [2. Thermal Receipt Studio](#2-thermal-receipt-studio)
  - [3. Terminal Administrative Services & Reversals](#3-terminal-administrative-services--reversals)
  - [4. Wire Protocol Telemetry Stream](#4-wire-protocol-telemetry-stream)
  - [5. Hardware Link Configuration](#5-hardware-link-configuration)
- [Connectivity & Setup](#connectivity--setup)
  - [TCP/IP (Wi-Fi / Local Network)](#tcpip-wi-fi--local-network)
  - [Serial (USB-C / COM Port)](#serial-usb-c--com-port)
- [Running the App](#running-the-app)
- [Code Structure](#code-structure)
- [NAPS TLV Protocol Reference](#naps-tlv-protocol-reference)
- [Common Terminal Response Codes](#common-terminal-response-codes)

---

## Overview

This example application serves as an interactive diagnostics, compliance testing, and integration sandbox for developers building POS, retail checkout, and kiosk solutions with the `naps_flutter` package.

It implements the official **NAPS EPT Machine-to-Machine (M2M) Protocol** specifications, handling:
- Inbound and outbound message packet framing with STX/ETX/LRC encapsulation.
- Two-phase commit debit authorizations (**TM 001** followed by **TM 002** within 40 seconds).
- Two-step transaction reversals and voids (**TM 003** lookup followed by **TM 004** cancellation).
- Duplicate receipt reprints (**TM 008**) for the last transaction or by historical STAN.
- End-of-day batch totals (**TM 010**).
- Terminal configuration print tickets (**TM 011**) and hardware soft resets (**TM 012**).
- Link probing and network latency tests (**TM 009**).

---

## Architecture & Modular Layout

The example app is organized into dedicated, single-responsibility modules under `lib/`:

```
lib/
├── main.dart                       # Lean application entry point and dark fintech theme
├── pages/
│   └── dashboard_page.dart         # Master state controller and tab orchestrator
├── widgets/
│   ├── app_header.dart             # Adaptive status header with live latency & probe link
│   ├── dashboard_nav_bar.dart      # Material 3 dark navigation bar with badge indicators
│   ├── operations_card.dart        # Hero amount display, presets, 40s countdown, TM 001 CTA
│   ├── receipt_preview_card.dart   # Thermal receipt canvas (#F9F9F6), customer/merchant tabs
│   ├── admin_services_card.dart    # Administrative operations grid (Duplicate, Void, Totals)
│   ├── telemetry_terminal.dart     # Wire protocol streaming terminal with live filter counters
│   └── connection_card.dart        # Hardware transport setup with USB auto-discovery
├── dialogs/
│   ├── cancellation_dialog.dart    # Two-step TM 003 query and TM 004 reversal modal
│   └── frame_inspector_sheet.dart  # Modal bottom sheet for parsed TLV analysis & hex dump
├── models/
│   ├── connection_type.dart        # ConnectionType enum (tcp, serial)
│   ├── log_filter.dart             # LogFilter enum (all, inbound, outbound, errors, success)
│   ├── log_item.dart               # LogItem data model with redaction & frame metadata
│   └── pending_confirmation.dart   # PendingManualConfirmation state model
└── constants/
    └── tag_descriptions.dart       # Human-readable dictionary of all official NAPS TLV tags
```

---

## Workbench Features

The application UI is structured into 5 separated tabs accessible via the bottom navigation bar:

### 1. Transaction Desk (Payment)
- **Hero Amount Input**: Large monospace currency input supporting Moroccan Dirham (MAD).
- **Quick Preset Buttons**: 1-tap selectors for common amounts (`10.00`, `25.00`, `50.00`, `100.00`, `250.00`).
- **Auto-Confirm Switch**:
  - **ON (Default)**: Automatically dispatches TM 002 immediately upon card authorization approval.
  - **OFF (Manual 2-Step)**: Displays an active **40-second countdown banner** with STAN tracking. If confirmed by the operator, TM 002 finalizes the debit; if aborted or timed out, the terminal automatically reverses the charge.
- **Cancel Token**: Allows aborting in-flight payment requests before card presentation.

### 2. Thermal Receipt Studio
- **Authentic Paper Canvas**: Renders thermal paper styling (`#F9F9F6`) with French thermal receipt typography and alignment rules.
- **Customer / Merchant Tabs**: Instantly switch between customer and merchant copies when both are generated.
- **Extracted Metadata Pills**: Highlights core transactional parameters (STAN, Authorization Number, Masked PAN, Date/Time).
- **One-Click Copy**: Copies the exact raw receipt line text to the system clipboard.
- **Empty State**: Guides operators when no receipt has been captured yet.

### 3. Terminal Administrative Services & Reversals
- **Duplicate Reprint (TM 008)**:
  - Leave blank to reprint the latest terminal transaction.
  - Enter a 6-digit STAN (or tap the history button to auto-fill the last STAN) to fetch a specific past transaction receipt.
- **Two-Step Void / Reversal (TM 003 / TM 004)**:
  - Step 1: Queries transaction status via **TM 003** with the target STAN.
  - Step 2: Renders verified card and transaction details for operator confirmation before dispatching **TM 004** to reverse the transaction.
- **Batch Totals Report (TM 010)**: Queries terminal daily transaction count, debit sum, and settlement totals.
- **Configuration Ticket (TM 011)**: Prints terminal network and merchant parameters.
- **Reset EPT (TM 012)**: Dispatches a soft reset command to clear pending states.

### 4. Wire Protocol Telemetry Stream
- **Live Frame Logging**: Bidirectional wire traffic streaming with millisecond timestamps (`HH:mm:ss.SSS`).
  - `>>` (Cyan): Outbound frames dispatched from the POS to the terminal.
  - `<<` (Amber): Inbound frames received from the terminal.
  - Green / Red: Operational success and error alerts.
- **High-Contrast Filter Pills**: Real-time category counters for `ALL`, `INBOUND`, `OUTBOUND`, `ERRORS`, and `SUCCESS`.
- **Search & Filter**: Search logs by STAN, TM code, hex bytes, or status text.
- **Frame Deep-Dive Inspector**: Tap any frame to open the bottom sheet displaying:
  - Message Type (TM) description.
  - Direction and exact byte count.
  - Decoded TLV fields mapped to human-readable names and formatted values.
  - Monospace Hex dump alongside ASCII representation.
  - Raw redacted wire payload for auditing.

### 5. Hardware Link Configuration
- **Transport Switcher**: Toggle seamlessly between **TCP/IP** and **Serial RS-232**.
- **USB Auto-Discovery**:
  - Automatically queries available USB and serial ports using native OS hooks.
  - Displays detected devices in a dropdown with descriptions (e.g. `COM3 (SUNMI P2 USB Serial)`).
  - Refresh button (`Icons.refresh`) to re-scan when hardware is plugged or unplugged.
  - Manual entry mode toggle for virtual or custom COM ports.
- **Fixed Protocol Fields**:
  - **TCP Port**: Fixed to port `4444` per protocol specification (read-only with lock indicator).
  - **POS Identifier (NCAI Tag 003)**: Fixed to `0030007` with live validation pill (`✓ VALID NCAI`).

---

## Connectivity & Setup

### TCP/IP (Wi-Fi / Local Network)
1. Ensure the SUNMI P2 terminal and the host device running this app are on the same Wi-Fi network or local subnet.
2. Verify the terminal's IP address on the SUNMI P2 screen (e.g., `192.168.1.26`).
3. Enter the terminal's IP address in the **Hardware Link Config** tab.
4. Tap the **Probe Link** button (`Icons.network_ping`) in the app bar to verify link responsiveness and measure round-trip latency (RTT).

### Serial (USB-C / COM Port)
1. Connect the SUNMI P2 to the host device using a USB-C data cable or docking station.
2. Select the **Serial (USB-C / COM)** option in the Link Config tab.
3. The app will automatically scan and populate detected ports in the **Detected USB Device** dropdown.
4. Set the baud rate (default: `9600 baud`, 8 data bits, 1 stop bit, no parity).

---

## Running the App

### Prerequisites
- Flutter SDK `>=3.11.5`
- Dart SDK `>=3.11.5`
- Connected physical device (Android, Windows, macOS, or Linux) or emulator.

### Commands

Run in debug mode:
```bash
cd naps_flutter/example
flutter run
```

Run in release mode (optimal performance for thermal rendering):
```bash
flutter run --release
```

Run static analysis:
```bash
flutter analyze
```

---

## NAPS TLV Protocol Reference

| Tag | Name | Description | Example Format |
|---|---|---|---|
| **001** | `TM` | Message Type Code | `001` (Payment), `002` (Confirm), `003` (Void Query), `004` (Void Confirm), `008` (Duplicate), `009` (Ping), `010` (Totals), `011` (Config), `012` (Reset) |
| **002** | `MT` | Transaction Amount | 12 numeric digits in cents (e.g., `000000003500` for 35.00 MAD) |
| **003** | `NCAI` | POS Station Identifier | Exactly 7 alphanumeric characters (e.g., `0030007`) |
| **004** | `NS` | Sequence Number | 6 numeric digits (incremental counter) |
| **005** | `NSA` | Target Sequence Number | 6 numeric digits (used when cancelling a past sequence) |
| **007** | `NCAR` | Masked Card PAN | Masked card number (e.g., `533576******8237`) |
| **008** | `STAN` | System Trace Audit Number | 6 numeric digits identifying the transaction |
| **009** | `NA` | Bank Authorization Code | Bank host authorization approval code |
| **010** | `DP` | Thermal Receipt Data | Formatted receipt text with control codes and line delimiters |
| **012** | `DE` | Currency Code | ISO numeric currency code (`504` = Moroccan Dirham / MAD) |
| **013** | `CR` | Response Code | 3 numeric digits (`000` = Approved) |
| **014** | `DA` | Date of Exchange | `DDMMYYYY` |
| **015** | `HE` | Time of Exchange | `HHMMSS` |
| **017** | `DAEX` | Card Expiry Date | `YYMM` |
| **040** | `EM` | Entry Mode | `CC` (Contactless / NFC) or `SC` (Smart Card / Chip) |

---

## Common Terminal Response Codes

| Response Code (CR) | Meaning | Status |
|---|---|---|
| `000` | **Transaction Approved** | Success |
| `117` | Transaction Declined | Card / Bank Refused |
| `480` | Already Done / Confirmed | Success (Idempotent) |
| `481` | Transaction Not Found / Already Reversed | Reversal lookup failed |
| `900` | General Error | Hardware or protocol fault |
| `909` | Communication Failure | Terminal link dropped |
