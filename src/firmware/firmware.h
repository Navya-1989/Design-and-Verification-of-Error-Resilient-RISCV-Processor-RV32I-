#ifndef FIRMWARE_H
#define FIRMWARE_H

#include <stdint.h>

#define reg_uart_clkdiv    (*(volatile uint32_t*)0x02000004)
#define reg_uart_data      (*(volatile uint32_t*)0x02000008)
#define reg_test_status    (*(volatile uint32_t*)0x03000000)
#define reg_test_signature (*(volatile uint32_t*)0x03000004)

#define TEST_STATUS_IDLE   0x00000000
#define TEST_STATUS_PASS   0x600d0001
#define TEST_STATUS_FAIL   0xbaad0001

#define TEST_SIGNATURE_PASS 0x00000000

#endif
