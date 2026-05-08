# Watchdog Monitor (TPS3431-like) + UART Configuration
## FPGA Extended Contest 2026 — Preliminary Round

**Team:** Utopia_EDABK  
**Authors:** Luong Xuan Thanh, Truong Dan Huy, Vu Thanh Hung, Le Viet Huy  
**Affiliation:** School of Electrical and Electronic Engineering, Hanoi University of Science and Technology (HUST)  
**Platform:** Kiwi 1P5 Board (Gowin GW1N-UV1P5)  
**HDL:** Verilog 
**System Clock:** 27 MHz

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure](#2-repository-structure)
3. [Architecture & Module Descriptions](#3-architecture--module-descriptions)
4. [Open-Drain Emulation on FPGA](#4-open-drain-emulation-on-fpga)
5. [Register Map](#5-register-map)
6. [UART Communication Protocol](#6-uart-communication-protocol)
7. [CLR_FAULT Feature](#7-clr_fault-feature)
8. [Pin Assignments & Constraints](#8-pin-assignments--constraints)
9. [LED Display Convention](#9-led-display-convention)
10. [How to Build](#10-how-to-build)
11. [How to Run the Demo on Board](#11-how-to-run-the-demo-on-board)

---

## 1. Project Overview

This design emulates the hardware watchdog supervisor function of the Texas Instruments TPS3431 IC. The system monitors a kick signal (WDI) and asserts a fault output (WDO, active-low) if no kick event is received within the configured timeout window (tWD). All timing parameters — tWD, tRST, and arm_delay — can be reconfigured at runtime via a UART interface using a frame-based protocol.

Default parameters after reset:

| Parameter     | Default Value | Description                              |
|---------------|---------------|------------------------------------------|
| tWD_ms        | 1600 ms       | Watchdog timeout (emulates CWD=NC mode)  |
| tRST_ms       | 200 ms        | WDO hold time during fault               |
| arm_delay_us  | 150 µs        | WDI ignore window after enabling         |

---

## 2. Repository Structure

```
.
├── wd_top_module.v         # Top-level structural module
├── watchdog_core.v         # Watchdog FSM + timing logic
├── regfile.v               # Configuration register file
├── frame_parser.v          # UART frame decoder and command executor
├── baudrate_gen.v          # Baud rate clock enable generator (115200 bps, 16x oversampling)
├── receiver.v              # UART receiver (8N1, 16x oversampled)
├── transmitter.v           # UART transmitter (8N1)
├── synchronizer.v          # 2-FF synchronizer + debounce + edge detection for S1/S2
├── frequency_divider.v     # Parameterized tick generator (produces tick_us and tick_ms)
├── internal_rst.v          # Power-on reset generator (active after 65536 clock cycles)
└── README.md
```

---

## 3. Architecture & Module Descriptions

The design follows a strictly synchronous, single-clock (27 MHz) architecture. All sub-modules share the same clock and a globally distributed active-high reset signal (`rst_n`) generated internally by `internal_rst`.

### 3.1 wd_top_module (Top Level)

Structural top-level that instantiates and interconnects all sub-modules. It exposes only five external ports: `clk`, `B_s1` (WDI button), `B_s2` (EN button), `uart_rx`, and `uart_tx`, plus two output signals `wdo` and `en_o`.

### 3.2 watchdog_core

Implements the core watchdog behavior using a synchronous always block with nested conditional logic (equivalent to the following states: RESET, ENABLE, TRANSITION/arm_delay, WAITING, KICK, FAULT, FAULT_EXPIRED, CLEAR_FAULT).

Behavior summary:
- On reset: watchdog is disabled, `wdo=1` (released), `en_o=0`, `FaultActive=0`.
- When `EN=0`: all counters are cleared, `wdo=1`, `FaultActive=0`.
- On `EN` 0→1 transition: the arm_delay counter begins. During this window, the WDI signal is ignored. `wdo=1` is held throughout.
- After arm_delay_us microseconds: `en_effective` is asserted, and the tWD counter starts incrementing on every millisecond tick.
- A valid kick (WDI falling edge, either from button or software) resets the tWD counter to zero.
- If `tWD_cnt >= tWD_ms`: `wdo` is pulled low, `FaultActive` is set, and the tRST counter begins.
- After `tRST_cnt >= tRST_ms`: `wdo` is released, `delay_cnt` is reset, and the system re-enters the arm_delay state to begin a new watchdog cycle.
- If `clr_fault_pulse` is asserted while `FaultActive=1`: WDO is immediately released, all counters are cleared, and the FSM re-enters arm_delay.

The WDI source is selected by `wdi_src` (CTRL register bit[1]): `0` selects the hardware button (wdi_button), `1` selects the software kick signal (wdi_sw, which is the logical inverse of kick_sw from regfile).

The EN source follows the same selection: when `wdi_src=0`, EN is driven by the physical button toggle (en_button); when `wdi_src=1`, EN is driven by CTRL register bit[0] (en_sw).

### 3.3 regfile

Stores all configuration and status registers. On reset, defaults are loaded. Implements write-enable logic for registers 0x00–0x0C and provides a combinational read path for all addresses including 0x10 (STATUS). The `clr_fault_pulse` signal is generated as a single-cycle pulse when CTRL bit[2] is written as 1; it is automatically cleared on the next clock cycle.

### 3.4 frame_parser

Two independent always blocks handle RX parsing and TX response generation. The RX FSM waits for the 0x55 header byte, then captures CMD, ADDR, LEN, up to 4 DATA bytes, and CHK. An internal `calc_chk` register accumulates the XOR of all bytes from CMD through DATA. If the received CHK matches `calc_chk`, `frame_rdy` is pulsed for one clock cycle. The TX FSM then constructs and sends the response frame byte-by-byte, waiting for `tx_busy` to de-assert between each byte.

### 3.5 baudrate_gen

Generates independent clock-enable pulses `rx_en` (16x baud rate = 1,843,200 Hz) and `tx_en` (1x baud rate = 115,200 Hz) from the 27 MHz system clock using integer division counters.

### 3.6 receiver

A 3-state FSM (S_START, S_DATA, S_STOP) with 16x oversampling. Samples each data bit at the center of the bit period (sample count 8 of 0–15). Asserts `rdy` after a complete 8N1 frame is received.

### 3.7 transmitter

A 4-state FSM (S_IDLE, S_START, S_DATA, S_STOP) that serializes 8-bit data into 8N1 UART frames on each `clk_en` (tx_en) pulse. `tx_busy` remains asserted from the start of transmission until the stop bit completes.

### 3.8 synchronizer_debounce_fallingedge

- S1 (WDI): passes through a 2-FF synchronizer, a 20 ms debounce counter, then a falling-edge detector. The output `wdi_button` is active-low: it is logic 0 for exactly one clock cycle when a valid falling edge is detected on S1.
- S2 (EN): passes through the same 2-FF synchronizer and 20 ms debounce. On each debounced falling edge, `en_button` toggles its state. This means a single press of S2 enables the watchdog, and a second press disables it.

### 3.9 frequency_divider

Parameterized module used twice in the top level:
- Instance `microsecond`: `CLK_FREQ_DESTINATION_HZ = 1_000_000` → produces a 1-cycle-wide `tick_us` pulse every 27 clock cycles (1 µs period).
- Instance `millisecond`: `CLK_FREQ_DESTINATION_HZ = 1_000` → produces a 1-cycle-wide `tick_ms` pulse every 27,000 clock cycles (1 ms period).

### 3.10 internal_rst

Holds `rst_n` low for exactly 65,536 clock cycles (~2.43 ms at 27 MHz) after FPGA power-on or configuration, then asserts `rst_n` high permanently. This ensures all flip-flops reach a known state before any logic becomes active.

---

## 4. Open-Drain Emulation on FPGA

**Chosen Approach: Option B — Push-pull output with active-low convention.**

- `wdo` output: logic 1 in normal/idle state (WDO released, equivalent to external pull-up), logic 0 when a fault is active (WDO pulled low). LED D3 is therefore ON when a fault is asserted (WDO=0).
- `en_o` output: logic 0 when the watchdog is disabled or during arm_delay, logic 1 after arm_delay completes and the watchdog is actively monitoring. LED D4 is ON when ENOUT=1.

In a real open-drain application, the `wdo` signal would drive the gate of an external N-channel MOSFET or be connected to a tri-state buffer output enable. In this FPGA demo context, the LED illumination convention described in Section 9 directly reflects the active-low WDO behavior.

---

## 5. Register Map

All registers are 32-bit wide and accessible at byte addresses. UART data is transmitted and received MSB-first within the 4-byte data field.

| Address | Name         | R/W | Width  | Description                                                                                   |
|---------|--------------|-----|--------|-----------------------------------------------------------------------------------------------|
| 0x00    | CTRL         | R/W | 32-bit | bit[0]: EN_SW (1=enable watchdog via software); bit[1]: WDI_SRC (0=button, 1=software); bit[2]: CLR_FAULT (write 1 to immediately release WDO) |
| 0x04    | tWD_ms       | R/W | 32-bit | Watchdog timeout in milliseconds. Default: 1600.                                             |
| 0x08    | tRST_ms      | R/W | 32-bit | WDO hold time during fault, in milliseconds. Default: 200.                                   |
| 0x0C    | arm_delay_us | R/W | 16-bit | WDI ignore window after enable, in microseconds. Default: 150. (Upper 16 bits ignored on write, returned as 0 on read.) |
| 0x10    | STATUS       | R   | 32-bit | bit[0]: EN_EFFECTIVE; bit[1]: FAULT_ACTIVE; bit[2]: ENOUT (=en_o); bit[3]: WDO (=wdo); bit[4]: LAST_KICK_SRC (0=button, 1=software) |

Notes:
- Writing to address 0x10 (STATUS) has no effect; it is read-only.
- The CLR_FAULT bit (CTRL bit[2]) is implemented as write-1-to-clear: the regfile generates a single-cycle `clr_fault_pulse` when this bit is written as 1, and it reads back as 0.
- CTRL bit[1] (WDI_SRC) also controls the EN source: 0 = EN from Button S2 toggle, 1 = EN from CTRL bit[0].

---

## 6. UART Communication Protocol

**Settings:** 115200 bps, 8 data bits, no parity, 1 stop bit (8N1).

### 6.1 Request Frame (Host → FPGA)

```
[0x55] [CMD] [ADDR] [LEN] [DATA byte 0] ... [DATA byte N-1] [CHK]
```

- **Header:** Always `0x55`.
- **CMD:** Command byte (see Section 6.3).
- **ADDR:** Register address (e.g., `0x00`, `0x04`).
- **LEN:** Number of DATA bytes that follow (0 for commands with no data payload).
- **DATA:** Up to 4 bytes. For 32-bit register writes, send 4 bytes MSB first.
- **CHK:** XOR of all bytes from CMD through the last DATA byte (inclusive).

### 6.2 Response Frame (FPGA → Host)

```
[0x55] [CMD | 0x80] [ADDR] [0x04] [DATA3] [DATA2] [DATA1] [DATA0] [CHK]
```

- The response CMD byte has bit[7] set (`CMD | 0x80`) to distinguish it from a request.
- The DATA field is always 4 bytes (the full 32-bit register value), sent MSB first.
- CHK is the XOR of all bytes from `[CMD | 0x80]` through `[DATA0]`.

### 6.3 Command Set

| CMD  | Name        | LEN | Description                                                     |
|------|-------------|-----|-----------------------------------------------------------------|
| 0x01 | WRITE_REG   | 1–4 | Write register at ADDR with DATA. Use LEN=4 for 32-bit values. |
| 0x02 | READ_REG    | 0   | Read register at ADDR. Returns the 32-bit register value.      |
| 0x03 | KICK        | 0   | Generate one software kick event (equivalent to one WDI falling edge). ADDR is ignored. |
| 0x04 | GET_STATUS  | 0   | Read STATUS register (equivalent to READ_REG with ADDR=0x10). ADDR field is ignored. |

### 6.4 Frame Examples

Enable watchdog via software (set CTRL = 0x00000001, WDI_SRC=0, EN_SW=1):
```
TX: 55 01 00 04 00 00 00 01 CHK
    CHK = 0x01 ^ 0x00 ^ 0x04 ^ 0x00 ^ 0x00 ^ 0x00 ^ 0x01 = 0x04
TX: 55 01 00 04 00 00 00 01 04
```

Set tWD to 500 ms (ADDR=0x04, DATA=0x000001F4):
```
TX: 55 01 04 04 00 00 01 F4 CHK
    CHK = 0x01 ^ 0x04 ^ 0x04 ^ 0x00 ^ 0x00 ^ 0x01 ^ 0xF4 = 0xF4
TX: 55 01 04 04 00 00 01 F4 F4
```

Send a software kick (CMD=0x03):
```
TX: 55 03 00 00 CHK
    CHK = 0x03 ^ 0x00 ^ 0x00 = 0x03
TX: 55 03 00 00 03
```

Read STATUS (CMD=0x04):
```
TX: 55 04 00 00 CHK
    CHK = 0x04 ^ 0x00 ^ 0x00 = 0x04
TX: 55 04 00 00 04
```

---

## 7. CLR_FAULT Feature

The CLR_FAULT mechanism allows the host to immediately terminate an active fault (WDO assertion) without waiting for the tRST timer to expire.

**Implementation:** When the host writes `0x00000004` (or any value with bit[2]=1) to the CTRL register (address 0x00), the `regfile` generates a single-cycle `clr_fault_pulse` signal. The `watchdog_core` monitors this pulse: if `FaultActive=1` at the time the pulse arrives, it immediately sets `wdo=1`, clears `FaultActive`, resets all counters (`tRST_cnt`, `tWD_cnt`, `delay_cnt`), and re-enters the arm_delay phase to begin a fresh watchdog cycle.

**Usage:** To use CLR_FAULT, send a WRITE_REG command to address 0x00 with bit[2] set. The bit is self-clearing and reads back as 0.

```
TX: 55 01 00 04 00 00 00 04 01
```

Note: CLR_FAULT has no effect if the watchdog is not currently in a fault state (FaultActive=0).

---

## 8. Pin Assignments & Constraints

The following pin assignments apply to the Kiwi 1P5 board (Gowin GW1N-UV1P5). All signals use LVCMOS33 I/O standard.

| Signal     | Board Resource | Net/IO         | Pin | Direction |
|------------|----------------|----------------|-----|-----------|
| clk        | 27 MHz OSC     | —              | 4   | Input     |
| B_s1 (WDI) | Button S1      | IOR1B (KEY1)   | 35  | Input     |
| B_s2 (EN)  | Button S2      | IOR1A (KEY2)   | 36  | Input     |
| wdo        | LED D3         | IOR17A (LED1)  | 27  | Output    |
| en_o       | LED D4         | IOR15B (LED2)  | 28  | Output    |
| uart_rx    | USB-UART GWU2U | IOR11B         | 33  | Input     |
| uart_tx    | USB-UART GWU2U | IOR11A         | 34  | Output    |

Declare these assignments in the Gowin `.cst` (physical constraints) file.

---

## 9. LED Display Convention

| LED        | Signal  | Logic 1 (LED ON)                              | Logic 0 (LED OFF)                            |
|------------|---------|-----------------------------------------------|----------------------------------------------|
| D4 (ENOUT) | en_o    | Watchdog is enabled and arm_delay has expired. The system is actively monitoring WDI. | Watchdog is disabled, or arm_delay is still counting. |
| D3 (WDO)   | wdo     | No fault: WDO is released (pull-up equivalent). LED D3 is OFF in normal operation. | Fault is active: WDO is pulled low. LED D3 turns ON for tRST_ms milliseconds to indicate a watchdog timeout event. |

Summary for the board demo:
- Both LEDs OFF after reset: normal disabled state.
- D4 turns ON after pressing S2 (EN) and waiting for arm_delay (~150 µs, not visible to the eye): watchdog is armed and running.
- D3 turns ON briefly (200 ms default) if no kick is received within 1600 ms: fault/timeout event.
- D3 turns OFF after tRST_ms, D4 stays ON, and a new watchdog cycle begins.
- Pressing S1 while D4 is ON resets the watchdog counter and prevents D3 from turning ON.

---

## 10. How to Build

### Requirements

- Gowin EDA (GOWIN FPGA Designer), version supporting GW1N-UV1P5 device.
- Target device: GW1N-UV1P5 (package as specified on the Kiwi 1P5 board).

### Steps

1. Open Gowin FPGA Designer and create a new project.
2. Select device: GW1N-UV1P5 (refer to the Kiwi 1P5 documentation for the exact package code).
3. Add all Verilog source files to the project:
   - `wd_top_module.v` (set as top-level module)
   - `watchdog_core.v`
   - `regfile.v`
   - `frame_parser.v`
   - `baudrate_gen.v`
   - `receiver.v`
   - `transmitter.v`
   - `synchronizer.v`
   - `frequency_divider.v`
   - `internal_rst.v`
4. Add the physical constraints file (`.cst`) with the pin assignments listed in Section 8.
5. Assign a 27MHz clock timing constraint to the 'clk' port using the `.sdc` file.
6. Run Synthesis.
7. Run Place & Route.
8. Generate the bitstream.

---

## 11. How to Run the Demo on Board

### Hardware Setup

1. Connect the Kiwi 1P5 board to the PC via the USB-UART (GWU2U) interface.
2. Program the board with the generated bitstream using the Gowin Programmer tool.
3. Open a serial terminal (e.g., PuTTY, Tera Term, or a Python script) on the PC. Remember to install the GWU2U USB-UART driver via Zadig.
   - Port: the COM port assigned to the GWU2U USB-UART adapter.
   - Settings: 115200 baud, 8 data bits, no parity, 1 stop bit (8N1).

### Demo Scenarios

**Scenario 1: Basic watchdog operation (hardware mode)**

1. After programming, both LEDs are OFF (watchdog disabled, reset state).
2. Press Button S2 once. After approximately 150 µs, LED D4 (ENOUT) turns ON — the watchdog is now armed.
3. Periodically press Button S1 (within 1600 ms between presses) to kick the watchdog. LED D3 remains OFF.
4. Stop pressing S1 and wait approximately 1600 ms. LED D3 (WDO) turns ON — fault is asserted.
5. After 200 ms, LED D3 turns OFF automatically — fault period expired, watchdog restarts.
6. Press S2 again to disable the watchdog. LED D4 turns OFF.

**Scenario 2: Software control via UART**

1. Send WRITE_REG to 0x00 with value `0x00000003` (EN_SW=1, WDI_SRC=1) to enable the watchdog in software mode.
2. LED D4 turns ON after arm_delay.
3. Periodically send the KICK command (`55 03 00 00 03`) to keep the watchdog alive.
4. Stop sending KICK commands. After 1600 ms, LED D3 turns ON.
5. To immediately clear the fault, send WRITE_REG to 0x00 with value `0x00000007` (EN_SW=1, WDI_SRC=1, CLR_FAULT=1): `55 01 00 04 00 00 00 07 02`. LED D3 turns OFF immediately.

**Scenario 3: Change tWD to 500 ms**

1. Ensure WDI_SRC=1 (software mode).
2. Send WRITE_REG to 0x04 with value `0x000001F4` (500 decimal): `55 01 04 04 00 00 01 F4 F4`.
3. The watchdog will now time out after 500 ms without a kick instead of 1600 ms.

**Scenario 4: Read STATUS**

1. Send GET_STATUS: `55 04 00 00 04`.
2. The FPGA responds with: `55 84 00 04 [DATA3] [DATA2] [DATA1] [DATA0] [CHK]`, where the 32-bit DATA field reflects the current STATUS register bits.


