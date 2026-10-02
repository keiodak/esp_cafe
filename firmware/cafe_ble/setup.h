// setup.h — the Cafe's ESP32 registers and its ADC / I2S setup (the original firmware, Peter Blasser)
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <esp_task_wdt.h>

#define FSMAGIC 0x0250FF0F //quieter than ? 0x0405FF08; //lowers parasitic noise floor
//try ff50ff08
//0xFF056408 from code example
 //timekeep-1 startwait5 standbywait100 rstbwait8
 //2 8 FF 8
// 2 16 FF 08
#define CLKDIVMAGIC ((8)<<9) //7 and 8 2<<7
#define BCKMAGIC 6<<6 //6 7
#define CLKMAGIC 6 //4
// cafe_ble: true = no Bluetooth (the default: BUTTON not held at power-on) — the radio clocks off and the ADC as
// the original firmware sets them
bool cafe_no_ble = true;
#define ADC1_PATT (0x6C<<24)
#define ADC2_PATT (0x0D<<24)

#define BIT(x) ((uint32_t) 1U << (x))
#define REG(x) ((volatile uint32_t *) (x))
#define CHANG(reg, val) REG(reg)[0] = (val); 
#define CHANGOR(reg, val) REG(reg)[0] |= (val); 
#define CHANGNO(reg, val) REG(reg)[0] &= ~(uint32_t)(val); 
#define CHANGNOR(reg, val)  CHANGOR(reg, val) \
 CHANGNO(reg, val)

#define SPI3_MISO_DLEN_REG  0x3ff64028
#define SPI3_CMD_REG  0x3ff65000
#define SPI3_CLOCK_REG  0x3ff65018
#define SPI3_PIN_REG  0x3ff65034
#define SPI3_W0_REG  0x3ff65080
#define SPI3_W8_REG  0x3ff650a0
#define SPI3_MOSI_DLEN_REG  0x3ff65028
#define SPI3_USER_REG  0x3ff6501C

#define DPORT_PERIP_CLK_EN_REG 0x3FF000C0
#define DPORT_PERIP_RST_EN_REG 0x3FF000C4
#define DPORT_WIFI_CLK_EN_REG 0x3FF000CC
#define IO_MUX_GPIO12ISH_REG 0x3FF49030

#define TIMG0_T0CONFIG_REG 0x3FF5F000
#define TIMG0_T0LO_REG 0x3FF5F004
#define TIMG0_T0UPDATE_REG 0x3FF5F00C

#define ESP32_SENS_SAR_DAC_CTRL1  0x3ff48898
#define ESP32_SENS_SAR_DAC_CTRL2  0x3ff4889C
#define ESP32_RTCIO_PAD_DAC1 0x3ff48484

#define DR_REG_SENS_BASE                        0x3ff48800
#define SENS_SAR_MEAS_WAIT2_REG          (DR_REG_SENS_BASE + 0x000c)
#define SENS_SAR_MEAS_CTRL_REG          (DR_REG_SENS_BASE + 0x0010)
#define SENS_SAR_TOUCH_ENABLE_REG          (DR_REG_SENS_BASE + 0x008c)
#define SENS_SAR_READ_CTRL2_REG          (DR_REG_SENS_BASE + 0x0090)
#define SENS_SAR_MEAS_CTRL2_REG          (DR_REG_SENS_BASE + 0x0a0)

#define DR_REG_SYSCON_BASE 0x3ff66000 //0x60002600
#define APB_SARADC_CTRL_REG (DR_REG_SYSCON_BASE + 0x10)
#define APB_SARADC_CTRL2_REG (DR_REG_SYSCON_BASE + 0x14)
#define APB_SARADC_FSM_REG (DR_REG_SYSCON_BASE + 0x18)
#define APB_SARADC_SAR1_PATT_TAB1_REG (DR_REG_SYSCON_BASE + 0x1C)
#define APB_SARADC_SAR2_PATT_TAB1_REG (DR_REG_SYSCON_BASE + 0x2C)

#define I2S_FIFO_RD_REG 0x3FF4F004 
#define I2S_CONF_REG 0x3FF4F008 
#define I2S_INT_ENA_REG 0x3FF4F014
#define I2S_INT_CLR_REG 0x3FF4F018
#define I2S_RXEOF_NUM_REG 0x3FF4F024
#define I2S_CONF_SINGLE_DATA_REG 0x3FF4F028

#define I2S_CONF1_REG 0x3FF4F0A0
#define I2S_CONF2_REG 0x3FF4F0A8
#define I2S_CLKM_CONF_REG 0x3FF4F0AC

#define I2S_SAMPLE_RATE_CONF_REG 0x3FF4F0B0
#define I2S_PDM_CONF_REG 0x3FF4F0B4
#define I2S_STATE_REG 0x3FF4F0BC
#define I2S_FIFO_CONF_REG 0x3FF4F020 
#define I2S_CONF_CHAN_REG 0x3FF4F02c
#define I2S_LC_CONF_REG 0x3FF4F060

#define I2S_IN_LINK_REG 0x3FF4F034

static inline void spin(volatile unsigned long count) {
  while (count--) asm volatile("nop");
}

static uint32_t dmall[3];

void initDIG() {
  if (cafe_no_ble) { CHANG(DPORT_WIFI_CLK_EN_REG,0) }   // (the original: radio clocks off. Only without Bluetooth)
  //SPI3 CLOCK
  CHANGOR(DPORT_PERIP_CLK_EN_REG,BIT(4))
  CHANGNOR(DPORT_PERIP_RST_EN_REG,BIT(4))
  //ADC POWER ALWAYS ON
  CHANGNO(SENS_SAR_MEAS_CTRL_REG,(uint32_t)0xFFFF)
  
  CHANG(SENS_SAR_MEAS_CTRL_REG,(uint32_t)0)
  CHANG(SENS_SAR_MEAS_CTRL2_REG,(uint32_t)0)
//LNA low noise amp example
CHANG(SENS_SAR_MEAS_CTRL_REG,(uint32_t)0xFF07338F) //default
  CHANG(SENS_SAR_MEAS_WAIT2_REG,BIT(18)|BIT(19)|BIT(17)|BIT(16)|0xFFF)

  CHANG(I2S_INT_ENA_REG,0) //disable interrupt
  CHANGNO(I2S_INT_CLR_REG,0)
  CHANG(I2S_CONF_REG,0)
  CHANGNOR(I2S_CONF_REG,BIT(1))//rx reset
  CHANGOR(I2S_CONF_REG,BIT(17)|BIT(9)) //msb right first
  
  CHANGNOR(I2S_CONF_REG,BIT(3)) //rx fifo reset
  CHANGOR(I2S_CONF1_REG,BIT(7))//PCM bypass
  
  //enable DMA
  CHANG(I2S_LC_CONF_REG,0)
  CHANGNOR(I2S_LC_CONF_REG,BIT(2))//ahb fifo rst
  CHANGNOR(I2S_LC_CONF_REG,BIT(3))//ahb reset
  CHANGNOR(I2S_LC_CONF_REG,BIT(0))//in rst
  CHANGOR(I2S_LC_CONF_REG,BIT(10))//burst inlink

  CHANG(I2S_CONF2_REG,0);//LCD enable
  CHANGOR(I2S_CONF2_REG,BIT(5));//LCD enable
  
  CHANG(I2S_FIFO_CONF_REG,BIT(12)|BIT(5)|BIT(20))
  CHANG(I2S_FIFO_CONF_REG,BIT(5)|BIT(20))
  CHANG(I2S_FIFO_CONF_REG,BIT(20))
  //NODMA
  //bit 16 is single channel|BIT(17)) is 32bit
  //20forcemod 16rxmod 12dmaconnect 5rxdatanum32
  CHANG(I2S_CONF_CHAN_REG,BIT(3)) //3singlechanrx
  CHANG(I2S_PDM_CONF_REG,0)
  CHANG(I2S_CLKM_CONF_REG,BIT(21)|CLKMAGIC)//clockenable
  //freq 2 is bad, 
  CHANGOR(I2S_SAMPLE_RATE_CONF_REG,(BCKMAGIC))
  //50
  
  //adc set i2s data len patterns should be zero 
  //adc set data pattern 
  CHANG(APB_SARADC_SAR1_PATT_TAB1_REG,ADC1_PATT)  
  CHANG(APB_SARADC_SAR2_PATT_TAB1_REG,ADC2_PATT)
  
  //adc set controller DIG
  /////////////////////adc 1 was on but now the force is gone
  //bottom bytes sample cycle and clock div
  
  CHANGOR(SENS_SAR_READ_CTRL2_REG,BIT(28)|BIT(29))
   //seems to not need bitmap
 
 
   // k.odk: with Bluetooth, SINGLE mode, ADC1 only (BIT(3) = double: ADC1 + ADC2 at once, as the original). The
   // radio's power detector takes ADC2 all the time, and in double mode that stalled every conversion: EARTH read 0.
   // EARTH (ADC2) is then read through the IDF driver instead (earth_tick in cafe_ble.ino).
   #define CTRLJING (BIT(26)|(CLKDIVMAGIC)|BIT(6)|BIT(2)|(cafe_no_ble ? BIT(3) : 0))   // no Bluetooth: double mode as the original
   
   #define CTRLPATT 0 //BIT(15)|BIT(19)
  #define CTRLJONG BIT(24)|BIT(23)
    //26datatoi2s 25sarsel 9clkdiv4 6clkgated 3double 2sar2mux
    //8 clock div 2   
      CHANG(APB_SARADC_CTRL_REG,CTRLJING|CTRLPATT)

  CHANG(APB_SARADC_FSM_REG,0xFF056408) //from code example
  CHANG(APB_SARADC_FSM_REG,0xFF056408) //from code example
  REG(APB_SARADC_FSM_REG)[0]=FSMAGIC;
 //timekeep-1 startwait5 standbywait100 rstbwait8

  CHANGNOR(APB_SARADC_CTRL_REG,CTRLJONG)
  CHANGOR(APB_SARADC_CTRL2_REG,BIT(10)|BIT(9)|BIT(0));
   CHANG(APB_SARADC_CTRL2_REG,BIT(10)|BIT(9)|BIT(1)|BIT(0));//trying to limit to 1

   //inverting and not inverting 10 and 9 data to adc ctrl no effect
   REG(SENS_SAR_TOUCH_ENABLE_REG)[0] = 0;

#define bufflough 7//3
dmall[0]=0xC0|BIT(bufflough+12)|BIT(bufflough);
  //owner dma, eof, 128, 128
  dmall[2]=0;
  uint32_t*muff=&dmall[0];

  CHANG(APB_SARADC_CTRL_REG,CTRLJONG|CTRLJING|CTRLPATT)
  
  
  CHANG(I2S_RXEOF_NUM_REG,BIT(bufflough-2))
    CHANG(I2S_RXEOF_NUM_REG,1)
  CHANGOR(I2S_IN_LINK_REG,(0xFFFFF&(int)muff))
  CHANGNOR(I2S_CONF_REG,BIT(1))//rx reset  
  CHANGNOR(I2S_CONF_REG,BIT(3)) //rx fifo reset
    CHANG(APB_SARADC_CTRL_REG,CTRLJING|CTRLPATT)
   //pattern pointer cleared
    CHANGOR(I2S_IN_LINK_REG,BIT(29))
    
    REG(I2S_INT_CLR_REG)[0]=0xFFFF;
  REG(I2S_CONF_REG)[0]=BIT(17)|BIT(9)|BIT(5); //start rx
}