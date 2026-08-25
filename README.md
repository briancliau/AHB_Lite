# SystemVerilog AMBA 3 AHB-Lite Master Controller

A modular, parameterizable **AMBA 3 AHB-Lite Master Interface** written in SystemVerilog. Designed to connect generic memory requests to standard AHB-Lite bus interconnect and subordiantes with full stall management, address-phase pipeline logic, and error handling.

---

## Features
* **AMBA 3 AHB-Lite Compliance:** Implements standard `HTRANS`, `HADDR`, `HWRITE`, `HSIZE`, `HRDATA`, `HWDATA`, `HREADY`, and `HRESP` signals. 
* **Pipelined Bus Protocol:** Decouples address and data phases to support full single-cycle throughput without insertable wait-states.
* **Stall & Ready Handling:** Safely pauses CPU/Master requests when target subordinates assert wait states (`HREADY = 0`).
* **Error Recovery:** Detects subordinate error conditions (`HRESP = 1`) and flags fault states to the manager.
* **Transfer Width:** Multi-size support (`HSIZE`) for Byte, Half-Word, and Word access alignment.
* **Verification-Ready:** Structured for seamless binding with SystemVerilog Assertions (SVA) to monitor protocol compliance.

---

## Signals and Interface Summary

### System Signals
| Signal | Direction | Description |
| :--- | :--- | :--- |
| `HCLK` | Input | System Clock |
| `HRESETn` | Input | Active-Low Asynchronous Reset |

### Master Output Signals (AHB Bus)
| Signal | Width | Description |
| :--- | :--- | :--- |
| `HADDR` | 32-bit | Byte address of the transfer |
| `HTRANS` | 2-bit | Transfer type (`IDLE` = 2'b00, `BUSY` = 2'b01, `NONSEQ` = 2'b10), `SEQ` = 2'b11 |
| `HWRITE` | 1-bit | Read (0) or Write (1) indication |
| `HSIZE` | 3-bit | Transfer size (Byte = 3'b000, Half-word = 3'b001, Word = 3'b010) |
| `HWDATA` | 32-bit | Write data bus (driven during Data Phase) |

### Slave Input Signals (AHB Bus)
| Signal | Width | Description |
| :--- | :--- | :--- |
| `HRDATA` | 32-bit | Read data bus |
| `HREADY` | 1-bit | Slave ready indicator (high when transfer complete) |
| `HRESP` | 1-bit | Slave transfer response (0 = OKAY, 1 = ERROR) |

---

## Bus Timing & Phase Behavior

The module manages the mandatory 2-phase AHB-Lite protocol overlapping:

```text
               Cycle 1       Cycle 2       Cycle 3
             +-------------+-------------+-------------+
HCLK         |  _  ¯¯¯  _  |  _  ¯¯¯  _  |  _  ¯¯¯  _  |
             +-------------+-------------+-------------+
HADDR        |   Address A |   Address B |    ...      |
             +-------------+-------------+-------------+
HTRANS       |   NONSEQ    |   NONSEQ    |    ...      |
             +-------------+-------------+-------------+
HWDATA/HRDATA|    (Idle)   |   Data A    |   Data B    |
             +-------------+-------------+-------------+
