# CORDIC Angle IP Block Using SPI Master

## Project Overview

This project implements a CORDIC (COordinate Rotation DIgital Computer) algorithm IP block on a Xilinx Zynq FPGA platform to calculate tilt angles from accelerometer data. The system uses an SPI Master interface to communicate with an ADXL345 accelerometer and processes the Y and Z axis data through a hardware CORDIC unit to compute the angle in real-time.

**Course:** EECE 423
**Authors:** Tarek Bshinnati & Soheil Haroun

## System Architecture

The system consists of the following major components:

1. **AXI Timer** - Triggers periodic sampling (500ms intervals) via interrupt
2. **SPI Master IP** - Custom AXI-Lite peripheral for SPI communication with ADXL345
3. **CORDIC Angle IP** - Custom AXI-Lite peripheral implementing vectoring mode CORDIC
4. **Software Application** - Zynq PS software coordinating data flow and displaying results

### Data Flow
```
AXI Timer → PS ISR (500 ms) → SPI Master (Part 1) → (X,Y,Z)
                ↓                                       ↓
        Software (atan2f)                    CORDIC Angle Unit
                                                       ↓
                                            ΘQ3.12 (hardware angle)
```

## Project Structure

```
.
├── README.md                          # This file
├── hdl/                               # Hardware Description Language files
│   ├── cordic/                        # CORDIC IP block Verilog files
│   │   ├── cordic_angle.v             # Top-level CORDIC module
│   │   └── cordic_angle_slave_lite_v1_0_S00_AXI.v  # AXI interface
│   └── spi/                           # SPI Master IP block Verilog files
│       ├── spi_master.v               # Top-level SPI module
│       ├── spi_master_core.v          # SPI core logic
│       ├── spi_master_cs.v            # Chip select control
│       └── spi_master_slave_lite_v1_0_S00_AXI.v    # AXI interface
├── software/                          # Embedded C software
│   └── main.c                         # Main application with test cases
├── constraints/                       # FPGA constraint files
│   └── spi_master_constraints.xdc     # Pin constraints for SPI signals
├── sim/                               # Simulation files
│   └── tb_cordic_waveform.wcfg        # Vivado waveform configuration
├── docs/                              # Documentation
│   ├── project_specification.pdf      # Project requirements and specifications
│   └── project_report.pdf             # Detailed project report
└── images/                            # Diagrams and screenshots
    ├── system_flow_diagram.png        # System data flow diagram
    ├── cordic_register_map.png        # CORDIC register definitions
    ├── cordic_datapath_specification.png  # CORDIC datapath details
    ├── cordic_algorithm_lut.png       # CORDIC LUT and algorithm
    ├── system_block_diagram.png       # Overall system block diagram
    ├── vivado_block_diagram.png       # Vivado IP integrator design
    ├── simulation_waveform.png        # Simulation waveform capture
    ├── console_output_1.png           # Console output example 1
    ├── console_output_2.png           # Console output example 2
    ├── terminal_output_1.png          # PuTTY terminal output 1
    └── terminal_output_2.png          # PuTTY terminal output 2
```

## Hardware Components

### CORDIC IP Block

The CORDIC module implements the vectoring mode algorithm to compute `atan2(Y, Z)` for any signed Y and Z values. It uses:

- **Input Format:** Signed 16-bit integers (Q15.0)
- **Output Format:** Signed 16-bit fixed-point angle in radians (Q3.12)
- **Iterations:** 13 iterations for convergence
- **Interface:** AXI4-Lite slave

#### Register Map
| Offset | Name      | Description                        |
|--------|-----------|-------------------------------------|
| 0x00   | C_Y       | Signed 16-bit input Y (bits[15:0]) |
| 0x04   | C_Z       | Signed 16-bit input Z (bits[15:0]) |
| 0x08   | C_CTRL    | bit 0 = start; other bits reserved |
| 0x0C   | C_STATUS  | bit 0 = done; other bits reserved  |
| 0x10   | C_ANGLE   | Signed Q3.12 output angle (radians)|

### SPI Master IP Block

Custom SPI Master implementing Mode 3 (CPOL=1, CPHA=1) for ADXL345 compatibility:

- **Clock Divider:** Configurable SPI clock generation
- **Data Width:** Supports variable byte transfers (1-7 bytes)
- **Interface:** AXI4-Lite slave

## Software Components

The embedded software (`software/main.c`) running on the Zynq PS includes:

- **SPI Driver:** Functions to read/write ADXL345 registers
- **ADXL345 Initialization:** Configures accelerometer for ±16g range
- **Timer ISR:** Periodic accelerometer sampling every 500ms
- **CORDIC Test Cases:** 6 predefined test vectors with validation
- **Real-time Angle Calculation:** Hardware vs. software comparison
- **Error Analysis:** Computes and displays angle errors

### Key Features

1. Reads ADXL345 device ID for verification
2. Configures accelerometer measurement mode
3. Implements interrupt-driven data acquisition
4. Compares hardware CORDIC against software `atan2f()`
5. Displays results in both radians and degrees

## Getting Started

### Prerequisites

- Xilinx Vivado Design Suite (2018.2 or later recommended)
- Xilinx SDK / Vitis
- Zynq-7000 Development Board (e.g., Zybo, ZedBoard)
- ADXL345 Accelerometer module
- Serial terminal (PuTTY, Tera Term, etc.)

### Building the Hardware

1. Open Vivado and create a new project
2. Add all Verilog files from `hdl/cordic/` and `hdl/spi/` directories
3. Create a block design in IP Integrator:
   - Add Zynq Processing System
   - Add custom SPI Master IP
   - Add custom CORDIC Angle IP
   - Add AXI Timer
   - Configure interrupts and interconnects
4. Add constraints from `constraints/spi_master_constraints.xdc`
5. Generate bitstream
6. Export hardware to SDK/Vitis

### Building the Software

1. Import hardware platform in Xilinx SDK/Vitis
2. Create a new application project
3. Use the code from `software/main.c`
4. Build the project
5. Program the FPGA and run the application

### Running the System

1. Connect ADXL345 to the FPGA board:
   - SPI_SCLK, SPI_MISO, SPI_MOSI, SPI_CS
   - VCC (3.3V), GND
2. Connect UART for serial output (115200 baud)
3. Program and run the system
4. Observe test case results followed by periodic angle readings

## Testing

The system includes 6 built-in test cases:

| Test | Y     | Z     | Description        |
|------|-------|-------|--------------------|
| 1    | 4096  | 4096  | 45° reference      |
| 2    | 0     | 4096  | 0° (vertical)      |
| 3    | 4096  | 0     | 90° (horizontal)   |
| 4    | 2048  | 4096  | ~26.57°            |
| 5    | -4096 | 4096  | -45° (negative)    |
| 6    | 256   | 512   | Small angle test   |

Each test displays:
- Hardware angle (from CORDIC)
- Software angle (from `atan2f()`)
- Error magnitude in degrees

## Performance

- **CORDIC Latency:** 13 clock cycles for computation
- **Sampling Rate:** 2 Hz (500ms timer interval)
- **Accuracy:** Typical error < 0.1° compared to software `atan2f()`
- **Fixed-Point Format:** Q3.12 provides range of ±π with resolution of ~0.00024 radians

## Future Enhancements

- Add X-axis processing for full 3D orientation
- Implement real-time plotting of angle data
- Add calibration routines for accelerometer offset compensation
- Optimize CORDIC iterations for faster computation
- Add UART communication for external control

## References

- CORDIC Algorithm: J.E. Volder, "The CORDIC Trigonometric Computing Technique"
- ADXL345 Datasheet: Analog Devices
- Xilinx AXI Reference Guide
- Zynq-7000 Technical Reference Manual

## License

This project was developed as coursework for EECE 423. All rights reserved by the authors.

## Acknowledgments

Special thanks to the EECE 423 course instructors and teaching assistants for their guidance and support throughout this project.
