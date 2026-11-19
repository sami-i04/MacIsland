
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);

static MRGetInfoFn getInfo;
static MRGetIsPlayingFn getIsPlaying;
static NSString *lastArtworkId;
static MRSendCommandFn sendCommand;
typedef void (*MRSetElapsedFn)(double);
static MRSetElapsedFn setElapsed;
static dispatch_source_t stdinSource;
static void writeLine(NSDictionary *o) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    if (fflush(stdout) != 0) exit(0);
}

static void emit(void) {
    getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef ref) {
        NSDictionary *info = (__bridge NSDictionary *)ref;
        getIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            NSMutableDictionary *o = [NSMutableDictionary dictionary];
            o[@"playing"] = @(playing);
            if (info) {
                id v;
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoTitle"]))    o[@"title"] = [v description];
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoArtist"]))   o[@"artist"] = [v description];
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoAlbum"]))    o[@"album"] = [v description];
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoDuration"])) o[@"duration"] = v;
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])) o[@"elapsed"] = v;
                if ((v = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"])) o[@"rate"] = v;
                id ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([ts isKindOfClass:[NSDate class]]) o[@"timestamp"] = @([(NSDate *)ts timeIntervalSince1970]);

                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([art isKindOfClass:[NSData class]] && art.length > 0) {
                    NSString *aid = [NSString stringWithFormat:@"%lu-%lu",
                                     (unsigned long)art.length, (unsigned long)art.hash];
                    o[@"artworkId"] = aid;
                    if (![aid isEqualToString:lastArtworkId]) {
                        o[@"artwork"] = [art base64EncodedStringWithOptions:0];
                        lastArtworkId = aid;
                    }
                } else {
                    lastArtworkId = nil;
                }
            }
            writeLine(o);
        });
    });
}

void macisland_stream(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "MediaRemote nicht ladbar\n"); exit(1); }
    getInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRRegisterFn reg = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !reg) { fprintf(stderr, "MediaRemote-Symbole fehlen\n"); exit(1); }

    sendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");

    stdinSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(stdinSource, ^{
        char buf[256];
        ssize_t n = read(STDIN_FILENO, buf, sizeof(buf) - 1);
        if (n <= 0) exit(0);
        buf[n] = 0;
        for (char *line = strtok(buf, "\n"); line; line = strtok(NULL, "\n")) {
            int cmd = -1;
            if (strcmp(line, "toggle") == 0) cmd = 2;
            else if (strcmp(line, "next") == 0) cmd = 4;
            else if (strcmp(line, "prev") == 0) cmd = 5;
            else if (strncmp(line, "seek ", 5) == 0) {
                double t = atof(line + 5);
                if (setElapsed && t >= 0) setElapsed(t);
            }
            if (cmd >= 0 && sendCommand) sendCommand(cmd, NULL);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ emit(); });
    });
    dispatch_resume(stdinSource);

    reg(dispatch_get_main_queue());
    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    ];
    for (NSString *n in names) {
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) { emit(); }];
    }

    [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { emit(); }];
    emit();
    CFRunLoopRun();
}
