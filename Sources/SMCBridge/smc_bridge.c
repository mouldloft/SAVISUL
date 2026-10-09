#include "smc_bridge.h"

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyDataInfo;

typedef struct {
    uint32_t key;
    SMCKeyDataVers vers;
    SMCKeyDataLimit pLimitData;
    SMCKeyDataInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static io_connect_t connection = 0;

static uint32_t fourcc(const char *text) {
    return ((uint32_t)(uint8_t)text[0] << 24) |
           ((uint32_t)(uint8_t)text[1] << 16) |
           ((uint32_t)(uint8_t)text[2] << 8) |
           (uint32_t)(uint8_t)text[3];
}

static void fan_key(char out[5], int index, const char *suffix) {
    out[0] = 'F';
    out[1] = (char)('0' + index);
    out[2] = suffix[0];
    out[3] = suffix[1];
    out[4] = '\0';
}

int sav_smc_open(void) {
    io_service_t service;
    kern_return_t result;
    if (connection != 0) {
        return 0;
    }
    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return -1;
    }
    result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS || connection == 0) {
        connection = 0;
        return -2;
    }
    return 0;
}

void sav_smc_close(void) {
    if (connection != 0) {
        IOServiceClose(connection);
        connection = 0;
    }
}

static int call_smc(const SMCKeyData *input, SMCKeyData *output) {
    SMCKeyData inCopy;
    SMCKeyData outCopy;
    size_t outSize = sizeof(outCopy);
    kern_return_t result;
    if (connection == 0 && sav_smc_open() != 0) {
        return -1;
    }
    inCopy = *input;
    memset(&outCopy, 0, sizeof(outCopy));
    result = IOConnectCallStructMethod(connection, 2, &inCopy, sizeof(inCopy), &outCopy, &outSize);
    if (result != KERN_SUCCESS) {
        return -3;
    }
    *output = outCopy;
    return 0;
}

static int read_key(const char *name, SMCKeyData *output) {
    SMCKeyData input;
    SMCKeyData info;
    uint32_t size;
    uint32_t type;
    memset(&input, 0, sizeof(input));
    memset(&info, 0, sizeof(info));
    input.key = fourcc(name);
    input.data8 = 9;
    if (call_smc(&input, &info) != 0) {
        return -3;
    }
    size = info.keyInfo.dataSize;
    type = info.keyInfo.dataType;
    if (size == 0 || size > 32) {
        return -2;
    }
    memset(&input, 0, sizeof(input));
    input.key = fourcc(name);
    input.data8 = 5;
    input.keyInfo.dataSize = size;
    if (call_smc(&input, output) != 0) {
        return -3;
    }
    output->keyInfo.dataSize = size;
    output->keyInfo.dataType = type;
    return 0;
}

static float decode_value(uint32_t type, const uint8_t *bytes) {
    if (type == 0x66706532) {
        return (float)(((uint16_t)bytes[0] << 8) | bytes[1]) / 4.0f;
    }
    if (type == 0x73703738) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        return (float)raw / 256.0f;
    }
    if (type == 0x666c7420) {
        uint32_t bits = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                        ((uint32_t)bytes[2] << 8) | bytes[3];
        bits = __builtin_bswap32(bits);
        float value;
        memcpy(&value, &bits, sizeof(value));
        return value;
    }
    if (type == 0x75693820) {
        return (float)bytes[0];
    }
    if (type == 0x75693136) {
        return (float)(((uint16_t)bytes[0] << 8) | bytes[1]);
    }
    if (type == 0x75693332) {
        return (float)(((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                       ((uint32_t)bytes[2] << 8) | bytes[3]);
    }
    return (float)(((uint16_t)bytes[0] << 8) | bytes[1]) / 4.0f;
}

static int read_number(const char *name, float *out) {
    SMCKeyData data;
    if (read_key(name, &data) != 0) {
        return -1;
    }
    *out = decode_value(data.keyInfo.dataType, data.bytes);
    return 0;
}

int sav_smc_read_fans(SAVFanReading *buffer, int capacity) {
    float countValue = 0;
    int count = 0;
    int index;
    if (buffer == 0 || capacity <= 0) {
        return -1;
    }
    if (sav_smc_open() != 0) {
        return -1;
    }
    if (read_number("FNum", &countValue) == 0 && countValue > 0 && countValue < 12) {
        count = (int)(countValue + 0.5f);
    } else {
        for (index = 0; index < capacity; index++) {
            char key[5];
            float actual = 0;
            fan_key(key, index, "Ac");
            if (read_number(key, &actual) != 0) {
                break;
            }
            count = index + 1;
        }
    }
    if (count <= 0) {
        return -1;
    }
    if (count > capacity) {
        count = capacity;
    }
    for (index = 0; index < count; index++) {
        char key[5];
        float actual = 0;
        float minimum = 0;
        float maximum = 0;
        float target = 0;
        fan_key(key, index, "Ac");
        read_number(key, &actual);
        fan_key(key, index, "Mn");
        read_number(key, &minimum);
        fan_key(key, index, "Mx");
        read_number(key, &maximum);
        fan_key(key, index, "Tg");
        read_number(key, &target);
        buffer[index].actual = actual;
        buffer[index].minimum = minimum;
        buffer[index].maximum = maximum > minimum ? maximum : actual;
        buffer[index].target = target;
    }
    return count;
}

int sav_smc_read_temperature(float *celsius) {
    static const char *keys[] = {"Tp01", "Tp05", "Tp09", "Tp0P", "TC0P", "Te05"};
    size_t i;
    if (celsius == 0 || sav_smc_open() != 0) {
        return -1;
    }
    for (i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        float value = 0;
        if (read_number(keys[i], &value) == 0 && value > 15.0f && value < 110.0f) {
            *celsius = value;
            return 0;
        }
    }
    return -1;
}

int sav_smc_describe(const char *key, char *buffer, int capacity) {
    SMCKeyData data;
    int count;
    if (buffer == 0 || capacity < 8 || key == 0) {
        return -1;
    }
    if (read_key(key, &data) != 0) {
        count = snprintf(buffer, (size_t)capacity, "unreadable");
        return count > 0 ? 0 : -1;
    }
    count = snprintf(
        buffer,
        (size_t)capacity,
        "type=%c%c%c%c size=%u value=%.1f result=%u",
        (char)((data.keyInfo.dataType >> 24) & 0xff),
        (char)((data.keyInfo.dataType >> 16) & 0xff),
        (char)((data.keyInfo.dataType >> 8) & 0xff),
        (char)(data.keyInfo.dataType & 0xff),
        data.keyInfo.dataSize,
        decode_value(data.keyInfo.dataType, data.bytes),
        data.result
    );
    return count > 0 ? 0 : -1;
}
