//
//  HLNotificationHandler.m
//  HotlineSDK
//
//  Created by Harish Kumar on 05/04/16.
//  Copyright © 2016 Freshdesk. All rights reserved.
//

#import "HLNotificationHandler.h"
#import "FDSecureStore.h"
#import "HLChannel.h"
#import "HLMacros.h"
#import "HotlineAppState.h"
#import "HLChannelViewController.h"
#import "FDMessageController.h"
#import "HLContainerController.h"
#import "FDMemLogger.h"
#import "FDChannelUpdater.h"
#import "FDMessagesUpdater.h"
#import "HLMessageServices.h"

@interface HLNotificationHandler ()

@property (nonatomic, strong) FDNotificationBanner *banner;
@property (nonatomic, strong) NSNumber *marketingID;

@end

@implementation HLNotificationHandler

- (instancetype)init{
    self = [super init];
    if (self) {
        self.banner = [FDNotificationBanner sharedInstance];
        self.banner.delegate = self;
    }
    return self;
}

+(BOOL)isHotlineNotification:(NSDictionary *)info{
    NSDictionary *payload = [HLNotificationHandler getPayloadFromNotificationInfo:info];
    return ([payload[@"source"] isEqualToString:@"konotor"] || [payload[@"source"] isEqualToString:@"hotline"]);
}

-(void)handleNotification:(NSDictionary *)info appState:(UIApplicationState)appState{
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            NSDictionary *payload = [HLNotificationHandler getPayloadFromNotificationInfo:info];

            [[[FDMessagesUpdater alloc]init]resetTime];
            
            NSNumber *channelID = nil;
            
            if ([payload objectForKey:HOTLINE_NOTIFICATION_PAYLOAD_CHANNEL_ID]) {
                channelID = @([payload[HOTLINE_NOTIFICATION_PAYLOAD_CHANNEL_ID] integerValue]);
            }else{
                return;
            }
            
            if ([payload objectForKey:HOTLINE_NOTIFICATION_PAYLOAD_MARKETING_ID]) {
                self.marketingID = @([payload[HOTLINE_NOTIFICATION_PAYLOAD_MARKETING_ID] integerValue]);
            }
            
            NSString *message = [payload valueForKeyPath:@"aps.alert"];
            
            HLChannel *channel = [HLChannel getWithID:channelID inContext:[KonotorDataManager sharedInstance].mainObjectContext];
            
            if (!channel){
                [[[FDChannelUpdater alloc] init]resetTime];
                [HLMessageServices fetchChannelsAndMessages:^(NSError *error){
                    if(!error){
                        NSManagedObjectContext *mContext = [KonotorDataManager sharedInstance].mainObjectContext;
                        [mContext performBlock:^{
                            @try {
                                HLChannel *ch = [HLChannel getWithID:channelID inContext:mContext];
                                if(ch){
                                    [self handleNotification:ch withMessage:message andState:appState];
                                }
                            }
                            @catch(NSException *exception) {
                                [FDMemLogger sendMessage:exception.description
                                              fromMethod:NSStringFromSelector(_cmd)];
                            }
                        }];
                    }
                }];
            }
            else {
                [HLMessageServices fetchChannelsAndMessages:nil];
                [self handleNotification:channel withMessage:message andState:appState];
            }
        }
        @catch(NSException *exception){
            [FDMemLogger sendMessage:exception.description fromMethod:NSStringFromSelector(_cmd)];
        }
    });
}

+(NSDictionary *)getPayloadFromNotificationInfo:(NSDictionary *)info{
    NSDictionary *payload = @{};
    if (info) {
        if ([info isKindOfClass:[NSDictionary class]]) {
            NSDictionary *launchOptions = info[@"UIApplicationLaunchOptionsRemoteNotificationKey"];
            if (launchOptions) {
                if ([launchOptions isKindOfClass:[NSDictionary class]]) {
                    payload = launchOptions;
                }else{
                    FDMemLogger *memlogger = [[FDMemLogger alloc]init];
                    [memlogger addMessage:[NSString stringWithFormat:@"payload for key UIApplicationLaunchOptionsRemoteNotificationKey -> %@ ",
                                           launchOptions]];
                    [memlogger upload];
                }
            }else{
                payload = info;
            }
        }else{
            FDMemLogger *memlogger = [[FDMemLogger alloc]init];
            [memlogger addMessage:[NSString stringWithFormat:@"Invalid push notification payload -> %@ ", info]];
            [memlogger upload];
        }
    }
    
    return payload;
}

-(void) showActiveStateNotificationBanner :(HLChannel *)channel withMessage:(NSString *)message{
    //Check active state because HLMessageServices can run in background and call this.
    if([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive){
        return;
    }
    BOOL bannerEnabled = [[FDSecureStore sharedInstance] boolValueForKey:HOTLINE_DEFAULTS_SHOW_NOTIFICATION_BANNER];
    if(bannerEnabled && ![channel isActiveChannel]){
        [self.banner setMessage:message];
        [self.banner displayBannerWithChannel:channel];
    }
}

- (void) handleNotification :(HLChannel *)channel withMessage:(NSString *)message andState:(UIApplicationState)state{
    if (state == UIApplicationStateInactive) {
        [HLMessageServices markMarketingMessageAsClicked:self.marketingID];
        [self launchMessageControllerOfChannel:channel];
    }
    else {
        [self showActiveStateNotificationBanner:channel withMessage:message];
    }
}

-(void)notificationBanner:(FDNotificationBanner *)banner bannerTapped:(id)sender{
    [HLMessageServices markMarketingMessageAsClicked:self.marketingID];
    [self launchMessageControllerOfChannel:banner.currentChannel];
}

-(void)launchMessageControllerOfChannel:(HLChannel *)channel{
    UIViewController *visibleSDKController = [HotlineAppState sharedInstance].currentVisibleController;
    if (visibleSDKController) {
        if ([visibleSDKController isKindOfClass:[HLChannelViewController class]]) {
            [self pushMessageControllerFrom:visibleSDKController.navigationController withChannel:channel];
        } else if ([visibleSDKController isKindOfClass:[FDMessageController class]]) {
            FDMessageController *msgController = (FDMessageController *)visibleSDKController;
            if (msgController.isModal) {
                if (![channel isActiveChannel]) {
                    [self presentMessageControllerOn:visibleSDKController withChannel:channel];
                }
            }else{
                UINavigationController *navController = msgController.navigationController;
                [navController popViewControllerAnimated:NO];
                [self pushMessageControllerFrom:navController withChannel:channel];
            }
        }else {
            [self presentMessageControllerOn:visibleSDKController withChannel:channel];
        }
        
    }else{
        [self presentMessageControllerOn:[self topMostController] withChannel:channel];
    }
}

-(UIViewController*) topMostController {
    UIViewController *topController = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

-(void)pushMessageControllerFrom:(UINavigationController *)controller withChannel:(HLChannel *)channel{
    FDMessageController *conversationController = [[FDMessageController alloc]initWithChannelID:channel.channelID andPresentModally:NO fromNotification:YES];
    HLContainerController *container = [[HLContainerController alloc]initWithController:conversationController andEmbed:NO];
    [controller pushViewController:container animated:YES];
}

-(void)presentMessageControllerOn:(UIViewController *)controller withChannel:(HLChannel *)channel{
    FDMessageController *messageController = [[FDMessageController alloc]initWithChannelID:channel.channelID andPresentModally:YES fromNotification:YES];
    HLContainerController *containerController = [[HLContainerController alloc]initWithController:messageController andEmbed:NO];
    UINavigationController *navigationController = [[UINavigationController alloc]initWithRootViewController:containerController];
    [controller presentViewController:navigationController animated:YES completion:nil];
}


+(BOOL) areNotificationsEnabled{
#if (TARGET_OS_SIMULATOR)
    return NO;
#else
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(currentUserNotificationSettings)]){
        UIUserNotificationSettings *noticationSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
        if (!noticationSettings || (noticationSettings.types == UIUserNotificationTypeNone)) {
            return NO;
        }
        return YES;
    }
    UIRemoteNotificationType types = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    if (types & UIRemoteNotificationTypeAlert){
        return YES;
    }
    return NO;
#endif
}

@end
