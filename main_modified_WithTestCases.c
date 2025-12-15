#include <stdio.h>
#include <math.h>
#include "xil_types.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xtmrctr.h"
#include "xil_exception.h"
#include"sleep.h"

// hw addresses
#define SPI_BASE 0x43C10000
#define CORDIC_BASE 0x43C00000
#define TMR_BASE 0x42800000
#define TMR_DEVICE_ID 0
#define TMR_INTR_ID 61
#define INTC_DEVICE_ID 0

// spi register offsets (corrected from verilog)
#define SPI_CFG_REG     0x00
#define SPI_TX_CNT_REG  0x04
#define SPI_TX_DATA0    0x08
#define SPI_TX_DATA1    0x0C
#define SPI_RX_DATA0    0x18
#define SPI_RX_DATA1    0x1C

// cordic offsets
#define CORDIC_Y_REG 0x00
#define CORDIC_Z_REG 0x04
#define CORDIC_CTRL_REG 0x08
#define CORDIC_STATUS_REG 0x0C
#define CORDIC_ANGLE_REG 0x10

// accel regs
#define ADXL_DEVID      0x00
#define ADXL_POWER_CTL  0x2D
#define ADXL_DATA_X0    0x32
#define ADXL_DATA_FORMAT 0x31

// reg access macros
#define WR_REG(base, off, val) (*((volatile unsigned int*)((base) + (off))) = (val))
#define RD_REG(base, off) (*((volatile unsigned int*)((base) + (off))))

// globals for isr
static short glob_y, glob_z;
static volatile int data_rdy = 0;
static int smpl_cnt = 0;

// hw instances
static XScuGic intc_inst;
static XTmrCtr tmr_inst;

void spi_wait_done() {
    usleep(5000);
}

void spi_write_reg(u8 addr, u8 data) {
    u32 txbuf;

    txbuf = ((u32)addr << 0) | ((u32)data << 8);
    WR_REG(SPI_BASE, SPI_TX_DATA0, txbuf);

    WR_REG(SPI_BASE, SPI_TX_CNT_REG, 2);

    spi_wait_done();
}

u8 spi_read_reg(u8 addr) {
    u32 txbuf;
    u32 rxbuf;

    txbuf = (0x80 | addr);
    WR_REG(SPI_BASE, SPI_TX_DATA0, txbuf);

    WR_REG(SPI_BASE, SPI_TX_CNT_REG, 2);

    spi_wait_done();

    rxbuf = RD_REG(SPI_BASE, SPI_RX_DATA0);
    return (u8)((rxbuf >> 8) & 0xFF);
}

void spi_init() {
    u8 devid;

    devid = spi_read_reg(ADXL_DEVID);
    xil_printf("ADXL345 Device ID: 0x%02X (expect 0xE5)\r\n", devid);

    if(devid != 0xE5) {
        xil_printf("WARNING: Wrong device ID!\r\n");
    }

    spi_write_reg(ADXL_DATA_FORMAT, 0x0B);
    usleep(10000);

    spi_write_reg(ADXL_POWER_CTL, 0x08);
    usleep(10000);

    xil_printf("ADXL345 configured\r\n");
}

void read_accel(short* x, short* y, short* z) {
    u32 rxlo, rxhi;
    u32 txbuf0, txbuf1;

    txbuf0 = (0xC0 | ADXL_DATA_X0);
    WR_REG(SPI_BASE, SPI_TX_DATA0, txbuf0);
    WR_REG(SPI_BASE, SPI_TX_DATA1, 0x00000000);

    WR_REG(SPI_BASE, SPI_TX_CNT_REG, 7);

    spi_wait_done();

    rxlo = RD_REG(SPI_BASE, SPI_RX_DATA0);
    rxhi = RD_REG(SPI_BASE, SPI_RX_DATA1);

    *x = (short)(((rxlo >> 8) & 0xFF) | ((rxlo >> 16) & 0xFF) << 8);
    *y = (short)(((rxlo >> 24) & 0xFF) | ((rxhi >> 0) & 0xFF) << 8);
    *z = (short)(((rxhi >> 8) & 0xFF) | ((rxhi >> 16) & 0xFF) << 8);
}

int cordic_calc(short yval, short zval) {
    WR_REG(CORDIC_BASE, CORDIC_Y_REG, (unsigned int)(yval & 0xFFFF));
    WR_REG(CORDIC_BASE, CORDIC_Z_REG, (unsigned int)(zval & 0xFFFF));

    WR_REG(CORDIC_BASE, CORDIC_CTRL_REG, 0x00);
    WR_REG(CORDIC_BASE, CORDIC_CTRL_REG, 0x01);

    while((RD_REG(CORDIC_BASE, CORDIC_STATUS_REG) & 0x01) == 0);

    return (int)(RD_REG(CORDIC_BASE, CORDIC_ANGLE_REG) & 0xFFFF);
}

float q312_to_rad(short qval) {
    return (float)qval / 4096.0f;
}

void cordic_tests() {
    short test_y[6] = {4096, 0, 4096, 2048, -4096, 256};
    short test_z[6] = {4096, 4096, 0, 4096, 4096, 512};
    int i;
    int hw_ang;
    float hw_rad, sw_rad;
    float hw_deg, sw_deg, err_deg;
    for(i=0;i<6;i++) {
        short y = test_y[i];
        short z = test_z[i];
        hw_ang = cordic_calc(y, z);
        hw_rad = q312_to_rad((short)hw_ang);
        hw_deg = hw_rad * 57.2958f;
        sw_rad = atan2f((float)y, (float)z);
        sw_deg = sw_rad * 57.2958f;
        err_deg = fabsf(hw_deg - sw_deg);
        xil_printf("TC %d: Y=%d Z=%d\r\n", i+1, y, z);
        xil_printf("  HW: %d.%02d deg\r\n", (int)hw_deg, (int)(hw_deg*100)%100);
        xil_printf("  SW: %d.%02d deg\r\n", (int)sw_deg, (int)(sw_deg*100)%100);
        xil_printf("  HW-SW Error: %d.%04d deg\r\n\r\n", (int)err_deg, (int)(err_deg*10000)%10000);
    }
}

void tmr_isr(void *cb_ref) {
    short tmp_x, tmp_y, tmp_z;

    read_accel(&tmp_x, &tmp_y, &tmp_z);

    glob_y = tmp_y;
    glob_z = tmp_z;

    data_rdy = 1;

    XTmrCtr *tmr_ptr = (XTmrCtr *)cb_ref;
    uint32_t csr = XTmrCtr_GetControlStatusReg(tmr_ptr->BaseAddress, 0);
    XTmrCtr_SetControlStatusReg(tmr_ptr->BaseAddress, 0, csr);
}

int setup_intr_sys(XScuGic *intc_ptr, XTmrCtr *tmr_ptr, u16 tmr_intr_id) {
    int sts;

    XScuGic_Config *intc_cfg = XScuGic_LookupConfig(INTC_DEVICE_ID);
    if (!intc_cfg) {
        return XST_FAILURE;
    }

    sts = XScuGic_CfgInitialize(intc_ptr, intc_cfg, intc_cfg->CpuBaseAddress);
    if (sts != XST_SUCCESS) {
        return sts;
    }

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler, intc_ptr);
    Xil_ExceptionEnable();

    sts = XScuGic_Connect(intc_ptr, tmr_intr_id,
        (Xil_ExceptionHandler)tmr_isr, (void *)tmr_ptr);
    if (sts != XST_SUCCESS) {
        return sts;
    }

    XScuGic_Enable(intc_ptr, tmr_intr_id);

    XScuGic_SetPriorityTriggerType(intc_ptr, tmr_intr_id, 0xA0, 0x3);

    return XST_SUCCESS;
}

int tmr_setup(XTmrCtr *tmr_ptr) {
    int sts;

    sts = XTmrCtr_Initialize(tmr_ptr, TMR_DEVICE_ID);
    if (sts != XST_SUCCESS) {
        return sts;
    }

    sts = XTmrCtr_SelfTest(tmr_ptr, 0);
    if (sts != XST_SUCCESS) {
        return sts;
    }

    XTmrCtr_SetOptions(tmr_ptr, 0,
        XTC_INT_MODE_OPTION | XTC_AUTO_RELOAD_OPTION);

    XTmrCtr_SetResetValue(tmr_ptr, 0, 16665000);

    XTmrCtr_Stop(tmr_ptr, 0);

    u32 tcsr = Xil_In32(TMR_BASE + 0x00);
    tcsr |= 0x02;
    tcsr |= 0x20;
    Xil_Out32(TMR_BASE + 0x00, tcsr);

    tcsr &= ~0x20;
    Xil_Out32(TMR_BASE + 0x00, tcsr);

    return XST_SUCCESS;
}

int main() {
    int hw_ang;
    float hw_rad, sw_rad, err_val;
    short loc_y, loc_z;
    int sts;

    xil_printf("\r\n===== CORDIC Tilt Angle System =====\r\n");
    xil_printf("Initializing ADXL345...\r\n");

    spi_init();

    xil_printf("ADXL345 ready\r\n");
    xil_printf("Running fixed CORDIC test cases...\r\n\r\n");
    cordic_tests();

    xil_printf("Setting up timer...\r\n");

    sts = tmr_setup(&tmr_inst);
    if (sts != XST_SUCCESS) {
        xil_printf("Timer setup failed\r\n");
        return XST_FAILURE;
    }

    sts = setup_intr_sys(&intc_inst, &tmr_inst, TMR_INTR_ID);
    if (sts != XST_SUCCESS) {
        xil_printf("Interrupt setup failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("Starting 500ms timer...\r\n\r\n");

    XTmrCtr_Start(&tmr_inst, 0);

    while(1) {
        if(data_rdy) {
            loc_y = glob_y;
            loc_z = glob_z;
            data_rdy = 0;

            hw_ang = cordic_calc(loc_y, loc_z);
            hw_rad = q312_to_rad((short)hw_ang);

            sw_rad = atan2f((float)loc_y, (float)loc_z);
            err_val = fabsf(hw_rad - sw_rad);

            if(smpl_cnt % 10 == 0) {
                xil_printf("Sample %d:\r\n", smpl_cnt);
                xil_printf("  Y=%d Z=%d\r\n", loc_y, loc_z);
                xil_printf("  HW: %d (Q3.12) = %d.%04d rad = %d.%02d deg\r\n",
                    hw_ang, (int)hw_rad, (int)(hw_rad*10000)%10000, 
                    (int)(hw_rad * 57.2958f), (int)(hw_rad * 5729.58f)%100);
                xil_printf("  SW: %d.%04d rad = %d.%02d deg\r\n",
                    (int)sw_rad, (int)(sw_rad*10000)%10000,
                    (int)(sw_rad * 57.2958f), (int)(sw_rad * 5729.58f)%100);
                xil_printf("  Err: %d.%04d rad = %d.%02d deg\r\n\r\n",
                    (int)err_val, (int)(err_val*10000)%10000,
                    (int)(err_val * 57.2958f), (int)(err_val * 5729.58f)%100);
            }

            smpl_cnt++;
        }
    }

    return 0;
}