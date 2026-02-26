#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *subtitle;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    if (self.body.length == 0) { [NSApp terminate:nil]; return; }
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional) {
            [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                completionHandler:^(BOOL granted, NSError *err) {
                    (void)granted; (void)err;
                    [self deliverWith:center];
                }];
        } else {
            [self deliverWith:center];
        }
    }];
}

- (void)deliverWith:(UNUserNotificationCenter *)center {
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized &&
            settings.authorizationStatus != UNAuthorizationStatusProvisional) {
            exit(1);
        }
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title    = self.title;
        content.body     = self.body;
        if (self.subtitle.length > 0) content.subtitle = self.subtitle;
        UNNotificationRequest *request = [UNNotificationRequest
            requestWithIdentifier:[[NSUUID UUID] UUIDString]
            content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError *err) {
            (void)err;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }];
    }];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        AppDelegate *delegate = [[AppDelegate alloc] init];
        delegate.title    = @"";
        delegate.body     = @"";
        delegate.subtitle = @"";

        for (int i = 1; i < argc; i++) {
            NSString *flag = [NSString stringWithUTF8String:argv[i]];
            if ([flag isEqualToString:@"-version"]) { printf("1.0\n"); return 0; }
            if (i + 1 < argc) {
                NSString *val = [NSString stringWithUTF8String:argv[i + 1]];
                if      ([flag isEqualToString:@"-title"])    { delegate.title    = val; i++; }
                else if ([flag isEqualToString:@"-message"])  { delegate.body     = val; i++; }
                else if ([flag isEqualToString:@"-subtitle"]) { delegate.subtitle = val; i++; }
            }
        }

        NSApplication *app = [NSApplication sharedApplication];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
