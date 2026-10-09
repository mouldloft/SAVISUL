// Now Playing bridge. Since macOS 15.4 MediaRemote only answers Apple-signed processes, so SAVISUL
// loads this library into /usr/bin/perl and reads one JSON line per change from its stdout.
// Commands arrive on stdin, one per line: toggle, play, pause, next, previous, seek <seconds>, refresh.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetPID)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSend)(int, NSDictionary *);
typedef void (*MRSetElapsed)(double);

static MRGetInfo getInfo;
static MRGetPID getPID;
static MRGetPlaying getPlaying;
static MRSend sendCommand;
static MRSetElapsed setElapsed;
static dispatch_queue_t queue;
static NSString *sentArtwork;
static dispatch_block_t pending;

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *text(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSNumber *number(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

static void refresh(void) {
    getPID(queue, ^(int pid) {
        getPlaying(queue, ^(BOOL playing) {
            getInfo(queue, ^(NSDictionary *info) {
                @autoreleasepool {
                    NSMutableDictionary *out = [NSMutableDictionary dictionary];
                    out[@"pid"] = @(pid);
                    out[@"playing"] = @(playing);
                    out[@"title"] = text(info, @"kMRMediaRemoteNowPlayingInfoTitle");
                    out[@"artist"] = text(info, @"kMRMediaRemoteNowPlayingInfoArtist");
                    out[@"album"] = text(info, @"kMRMediaRemoteNowPlayingInfoAlbum");
                    out[@"duration"] = number(info, @"kMRMediaRemoteNowPlayingInfoDuration");
                    out[@"elapsed"] = number(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
                    out[@"rate"] = number(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
                    id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    out[@"timestamp"] = [stamp isKindOfClass:[NSDate class]] ? @([(NSDate *)stamp timeIntervalSince1970])
                                                                             : @([[NSDate date] timeIntervalSince1970]);
                    NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if ([art isKindOfClass:[NSData class]] && art.length > 0) {
                        id identifier = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
                        NSString *key = identifier ? [NSString stringWithFormat:@"%@", identifier]
                                                   : [NSString stringWithFormat:@"%lu-%lu", (unsigned long)art.length, (unsigned long)art.hash];
                        out[@"artworkID"] = key;
                        if (![key isEqualToString:sentArtwork]) {
                            out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                            sentArtwork = key;
                        }
                    } else {
                        sentArtwork = nil;
                    }
                    emit(out);
                }
            });
        });
    });
}

/// Several notifications arrive together for one change; answer once.
static void schedule(void) {
    if (pending) dispatch_block_cancel(pending);
    pending = dispatch_block_create(0, ^{ refresh(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), queue, pending);
}

static NSString *symbolString(void *handle, const char *name) {
    NSString *__unsafe_unretained *pointer = (NSString *__unsafe_unretained *)dlsym(handle, name);
    return pointer ? *pointer : [NSString stringWithUTF8String:name];
}

static void readCommands(void) {
    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        size_t length = strlen(line);
        while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) line[--length] = 0;
        if (strcmp(line, "toggle") == 0) sendCommand(2, nil);
        else if (strcmp(line, "play") == 0) sendCommand(0, nil);
        else if (strcmp(line, "pause") == 0) sendCommand(1, nil);
        else if (strcmp(line, "next") == 0) sendCommand(4, nil);
        else if (strcmp(line, "previous") == 0) sendCommand(5, nil);
        else if (strncmp(line, "seek ", 5) == 0 && setElapsed) setElapsed(atof(line + 5));
        else if (strcmp(line, "refresh") == 0) dispatch_async(queue, ^{ refresh(); });
        dispatch_async(queue, ^{ schedule(); });
    }
    exit(0);
}

void savisul_media_run(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!handle) {
            emit(@{@"error": @"framework"});
            exit(2);
        }
        getInfo = (MRGetInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        getPID = (MRGetPID)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
        getPlaying = (MRGetPlaying)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        sendCommand = (MRSend)dlsym(handle, "MRMediaRemoteSendCommand");
        setElapsed = (MRSetElapsed)dlsym(handle, "MRMediaRemoteSetElapsedTime");
        MRRegister registerForNotifications = (MRRegister)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (!getInfo || !getPID || !getPlaying || !sendCommand || !registerForNotifications) {
            emit(@{@"error": @"symbols"});
            exit(2);
        }
        queue = dispatch_queue_create("com.savisul.media", DISPATCH_QUEUE_SERIAL);
        registerForNotifications(queue);
        const char *names[] = {
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationClientStateDidChange"
        };
        for (size_t index = 0; index < sizeof names / sizeof names[0]; index++) {
            [[NSNotificationCenter defaultCenter] addObserverForName:symbolString(handle, names[index]) object:nil queue:nil
                                                          usingBlock:^(NSNotification *note) { dispatch_async(queue, ^{ schedule(); }); }];
        }
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 4 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(timer, ^{ refresh(); });
        dispatch_resume(timer);
        [NSThread detachNewThreadWithBlock:^{ readCommands(); }];
        emit(@{@"ready": @YES});
        CFRunLoopRun();
    }
}
