#ifndef SAV_SMC_BRIDGE_H
#define SAV_SMC_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SAVFanReading {
    float actual;
    float minimum;
    float maximum;
    float target;
} SAVFanReading;

int sav_smc_open(void);
void sav_smc_close(void);
int sav_smc_read_fans(SAVFanReading *buffer, int capacity);
int sav_smc_read_temperature(float *celsius);
int sav_smc_describe(const char *key, char *buffer, int capacity);

#ifdef __cplusplus
}
#endif

#endif
