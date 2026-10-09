// SAVISUL fan helper. Runs as root from launchd, because only root may write the SMC fan keys.
// It listens on a local socket for the one user who installed it and does three things:
//   status            report each fan's speed, limits, target and mode
//   set <rpm>         hold every fan at that speed, clamped to the fan's own minimum and maximum
//   auto              give the fans back to macOS
// If SAVISUL stops checking in for 60 seconds, or the helper is stopped, macOS gets the fans back.
//
// Build: clang -O2 -framework IOKit -o savisul-fan-helper fan_helper.c
// Usage: savisul-fan-helper --serve --owner <uid> [--socket <path>]   (root, from launchd)
//        savisul-fan-helper --status                                  (any user, read only)

#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <mach/mach.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define HELPER_VERSION "1"
#define DEFAULT_SOCKET "/var/run/com.savisul.fans.sock"
#define MAX_FANS 8
#define WATCHDOG_SECONDS 60

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } SMCLimit;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCLimit limit;
    SMCInfo info;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCData;

enum { kReadBytes = 5, kWriteBytes = 6, kKeyInfo = 9 };

static io_connect_t smc = 0;
static int fanCount = 0;
static int forced = 0;
static int originalMode[MAX_FANS];
static int haveOriginal = 0;
static time_t lastContact = 0;
static volatile sig_atomic_t stopping = 0;

static uint32_t fourcc(const char *t) {
    return ((uint32_t)(uint8_t)t[0] << 24) | ((uint32_t)(uint8_t)t[1] << 16) | ((uint32_t)(uint8_t)t[2] << 8) | (uint32_t)(uint8_t)t[3];
}

static int smc_open(void) {
    if (smc) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &smc);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? 0 : -1;
}

static int smc_call(SMCData *in, SMCData *out) {
    size_t size = sizeof(SMCData);
    memset(out, 0, sizeof(SMCData));
    return IOConnectCallStructMethod(smc, 2, in, sizeof(SMCData), out, &size) == KERN_SUCCESS ? 0 : -1;
}

static int key_info(const char *name, SMCInfo *info) {
    SMCData in, out;
    memset(&in, 0, sizeof in);
    in.key = fourcc(name);
    in.data8 = kKeyInfo;
    if (smc_call(&in, &out) != 0 || out.result != 0 || out.info.dataSize == 0 || out.info.dataSize > 32) return -1;
    *info = out.info;
    return 0;
}

static int read_key(const char *name, SMCInfo *info, uint8_t bytes[32]) {
    SMCData in, out;
    if (key_info(name, info) != 0) return -1;
    memset(&in, 0, sizeof in);
    in.key = fourcc(name);
    in.data8 = kReadBytes;
    in.info.dataSize = info->dataSize;
    if (smc_call(&in, &out) != 0 || out.result != 0) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

static int write_key(const char *name, const uint8_t *bytes, uint32_t size) {
    SMCInfo info;
    SMCData in, out;
    if (key_info(name, &info) != 0 || info.dataSize != size) return -1;
    memset(&in, 0, sizeof in);
    in.key = fourcc(name);
    in.data8 = kWriteBytes;
    in.info.dataSize = size;
    memcpy(in.bytes, bytes, size);
    if (smc_call(&in, &out) != 0 || out.result != 0) return -1;
    return 0;
}

// 'flt ' values are little-endian floats; older Macs use big-endian 'fpe2' fixed point.
static float decode(const SMCInfo *info, const uint8_t *b) {
    if (info->dataType == fourcc("flt ")) { float v; memcpy(&v, b, 4); return v; }
    if (info->dataType == fourcc("fpe2")) return (float)(((uint16_t)b[0] << 8) | b[1]) / 4.0f;
    if (info->dataType == fourcc("ui8 ")) return (float)b[0];
    if (info->dataType == fourcc("ui16")) return (float)(((uint16_t)b[0] << 8) | b[1]);
    return 0;
}

static float read_float(const char *name) {
    SMCInfo info;
    uint8_t bytes[32];
    return read_key(name, &info, bytes) == 0 ? decode(&info, bytes) : -1;
}

static int write_float(const char *name, float value) {
    SMCInfo info;
    uint8_t bytes[4];
    if (key_info(name, &info) != 0) return -1;
    if (info.dataType == fourcc("flt ")) {
        memcpy(bytes, &value, 4);
        return write_key(name, bytes, 4);
    }
    if (info.dataType == fourcc("fpe2")) {
        uint16_t raw = (uint16_t)(value * 4.0f);
        bytes[0] = (uint8_t)(raw >> 8);
        bytes[1] = (uint8_t)raw;
        return write_key(name, bytes, 2);
    }
    return -1;
}

static int write_u8(const char *name, uint8_t value) { return write_key(name, &value, 1); }

static void fan_key(char out[5], int index, const char *suffix) {
    snprintf(out, 5, "F%d%c%c", index, suffix[0], suffix[1]);
}

static int count_fans(void) {
    float n = read_float("FNum");
    if (n > 0 && n <= MAX_FANS) return (int)(n + 0.5f);
    int count = 0;
    char key[5];
    for (int i = 0; i < MAX_FANS; i++) {
        fan_key(key, i, "Ac");
        if (read_float(key) < 0) break;
        count = i + 1;
    }
    return count;
}

static void restore_auto(void) {
    char key[5];
    for (int i = 0; i < fanCount; i++) {
        fan_key(key, i, "Md");
        write_u8(key, haveOriginal ? (uint8_t)originalMode[i] : 0);
    }
    SMCInfo info;
    if (key_info("Ftst", &info) == 0) write_u8("Ftst", 0);
    forced = 0;
}

static int set_speed(float rpm) {
    char key[5];
    SMCInfo info;
    if (!haveOriginal) {
        for (int i = 0; i < fanCount; i++) {
            fan_key(key, i, "Md");
            float mode = read_float(key);
            originalMode[i] = mode >= 0 ? (int)mode : 0;
        }
        haveOriginal = 1;
    }
    // Apple silicon only accepts manual targets after the fan test flag is raised.
    if (key_info("Ftst", &info) == 0) write_u8("Ftst", 1);
    int failures = 0;
    for (int i = 0; i < fanCount; i++) {
        char minKey[5], maxKey[5];
        fan_key(minKey, i, "Mn");
        fan_key(maxKey, i, "Mx");
        float lo = read_float(minKey), hi = read_float(maxKey);
        float target = rpm;
        if (lo > 0 && target < lo) target = lo;
        if (hi > lo && target > hi) target = hi;
        fan_key(key, i, "Md");
        if (write_u8(key, 1) != 0) failures++;
        fan_key(key, i, "Tg");
        if (write_float(key, target) != 0) failures++;
    }
    forced = failures == 0;
    if (!forced) restore_auto();
    return failures == 0 ? 0 : -1;
}

static void status_line(char *out, size_t size) {
    size_t used = (size_t)snprintf(out, size, "ok fans=%d forced=%d", fanCount, forced);
    char key[5];
    for (int i = 0; i < fanCount && used < size; i++) {
        float values[5];
        const char *suffixes[] = {"Ac", "Mn", "Mx", "Tg", "Md"};
        for (int k = 0; k < 5; k++) { fan_key(key, i, suffixes[k]); values[k] = read_float(key); }
        used += (size_t)snprintf(out + used, size - used, " F%d=%.0f,%.0f,%.0f,%.0f,%.0f", i, values[0], values[1], values[2], values[3], values[4]);
    }
    if (used < size) snprintf(out + used, size - used, "\n");
}

static void handle(const char *line, char *reply, size_t size) {
    lastContact = time(NULL);
    if (strncmp(line, "hello", 5) == 0) snprintf(reply, size, "ok savisul-fans %s\n", HELPER_VERSION);
    else if (strncmp(line, "status", 6) == 0) status_line(reply, size);
    else if (strncmp(line, "ping", 4) == 0) snprintf(reply, size, "ok\n");
    else if (strncmp(line, "auto", 4) == 0) { restore_auto(); snprintf(reply, size, "ok\n"); }
    else if (strncmp(line, "set ", 4) == 0) {
        float rpm = strtof(line + 4, NULL);
        if (rpm <= 0 || rpm > 20000) snprintf(reply, size, "error range\n");
        else snprintf(reply, size, set_speed(rpm) == 0 ? "ok\n" : "error smc\n");
    } else snprintf(reply, size, "error command\n");
}

static void on_signal(int sig) { (void)sig; stopping = 1; }

static int serve(const char *path, uid_t owner) {
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGPIPE, SIG_IGN);
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return 1;
    struct sockaddr_un address;
    memset(&address, 0, sizeof address);
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path, sizeof address.sun_path);
    unlink(path);
    if (bind(server, (struct sockaddr *)&address, sizeof address) != 0 || listen(server, 4) != 0) return 1;
    chmod(path, 0666);
    while (!stopping) {
        fd_set read;
        FD_ZERO(&read);
        FD_SET(server, &read);
        struct timeval wait = {5, 0};
        int ready = select(server + 1, &read, NULL, NULL, &wait);
        if (forced && time(NULL) - lastContact > WATCHDOG_SECONDS) restore_auto();
        if (ready <= 0) continue;
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        uid_t uid;
        gid_t gid;
        if (getpeereid(client, &uid, &gid) != 0 || (uid != owner && uid != 0)) { close(client); continue; }
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
        char buffer[256];
        ssize_t n = recv(client, buffer, sizeof buffer - 1, 0);
        if (n > 0) {
            buffer[n] = 0;
            char reply[512];
            handle(buffer, reply, sizeof reply);
            send(client, reply, strlen(reply), 0);
        }
        close(client);
    }
    if (forced) restore_auto();
    close(server);
    unlink(path);
    return 0;
}

int main(int argc, char **argv) {
    const char *path = DEFAULT_SOCKET;
    int serving = 0, status = 0;
    long owner = -1;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--serve") == 0) serving = 1;
        else if (strcmp(argv[i], "--status") == 0) status = 1;
        else if (strcmp(argv[i], "--owner") == 0 && i + 1 < argc) owner = strtol(argv[++i], NULL, 10);
        else if (strcmp(argv[i], "--socket") == 0 && i + 1 < argc) path = argv[++i];
    }
    if (smc_open() != 0) { fprintf(stderr, "no SMC\n"); return 2; }
    fanCount = count_fans();
    if (status) {
        char line[512];
        status_line(line, sizeof line);
        fputs(line, stdout);
        return 0;
    }
    if (!serving || owner < 0) {
        fprintf(stderr, "usage: %s --serve --owner <uid> [--socket path] | --status\n", argv[0]);
        return 64;
    }
    return serve(path, (uid_t)owner);
}
