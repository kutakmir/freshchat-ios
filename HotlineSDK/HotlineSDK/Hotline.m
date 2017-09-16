//
//  Hotline.m
//  Konotor
//
//  Created by AravinthChandran on 9/7/15.
//  Copyright (c) 2015 Freshdesk. All rights reserved.
//

#import "Hotline.h"
#import "HLContainerController.h"
#import "HLCategoryListController.h"
#import "HLCategoryGridViewController.h"
#import "FDReachabilityManager.h"
#import "HLChannelViewController.h"
#import "KonotorDataManager.h"
#import "FDMessageController.h"
#import "FDSecureStore.h"
#import "HLMacros.h"
#import "Konotor.h"
#import "HLCoreServices.h"
#import "FDUtilities.h"
#import "FDSolutionUpdater.h"
#import "FDMessagesUpdater.h"
#import "Message.h"
#import "HLConstants.h"
#import "HLMessageServices.h"
#import "KonotorCustomProperty.h"
#import "KonotorUser.h"
#import "HLVersionConstants.h"
#import "HLNotificationHandler.h"
#import "HLTagManager.h"
#import "HLArticlesController.h"
#import "HLArticleDetailViewController.h"
#import "FDIndex.h"
#import "KonotorMessageBinary.h"
#import "FDLocalNotification.h"
#import "FDPlistManager.h"
#import "FDMemLogger.h"
#import "HLInterstitialViewController.h"
#import "HLControllerUtils.h"
#import "HLMessagePoller.h"
#import "FDThemeConstants.h"
#import "FDUtilities.h"
#import "FDLocaleUtil.h"
#import "FDConstants.h"
#import "HLUserDefaults.h"
#import "HLUser.h"
#import "FDImageView.h"

@interface Hotline ()

@property(nonatomic, strong, readwrite) FreshchatConfig *config;
@property (nonatomic, assign) BOOL showChannelThumbnail;
@property (nonatomic, strong) HLNotificationHandler *notificationHandler;
@property (nonatomic, strong) HLMessagePoller *messagePoller;

@end

@interface FreshchatUser ()

-(void)resetUser;

@end

@implementation FreshchatOptions

@end

@implementation Hotline

+(instancetype)sharedInstance{
    
    @try {
        static Hotline *sharedInstance = nil;
        static dispatch_once_t oncetoken;
        dispatch_once(&oncetoken,^{
            sharedInstance = [[Hotline alloc]init];
        });
        if(![sharedInstance checkPersistence]) {
            return nil;
        }
        return sharedInstance;
        
    } @catch (NSException *exception) {
        [FDMemLogger sendMessage:exception.description fromMethod:NSStringFromSelector(_cmd)];
        return nil; // Return a valid value to avoid inconsistency
    }
}

+(NSString *)SDKVersion{
    return HOTLINE_SDK_VERSION;
}

-(BOOL)checkPersistence {
    if(![[KonotorDataManager sharedInstance] isReady]){
        return false;
    }
    return true;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        [FDIndex load];
        [KonotorMessageBinary load];
        [[FDReachabilityManager sharedInstance] start];
        [self registerAppNotificationListeners];
        self.messagePoller = [[HLMessagePoller alloc] initWithPollType:OffScreenPollFetch];
    }
    return self;
}

-(void)networkReachable{
    [FDUtilities initiatePendingTasks];
}

-(void)initWithConfig:(FreshchatConfig *)config{
    @try {
        [self initWithConfig:config completion:nil];
    } @catch (NSException *exception) {
        [FDMemLogger sendMessage:exception.description fromMethod:NSStringFromSelector(_cmd)];
    }
}

-(void)initWithConfig:(FreshchatConfig *)config completion:(void(^)(NSError *error))completion{
    FreshchatConfig *processedConfig = [self processConfig:config];
    
    self.config = processedConfig;
    
    if ([self hasUpdatedConfig:processedConfig]) {
        [self cleanUpData:^{
            [self updateConfig:processedConfig andRegisterUser:completion];
        }];
    }
    else {
        [self updateConfig:processedConfig andRegisterUser:completion];
    }
}

-(FreshchatConfig *)processConfig:(FreshchatConfig *)config{
    config.appID  = trimString(config.appID);
    config.appKey = trimString(config.appKey);
    config.domain = [self validateDomain: config.domain];
    
    if(config.pollWhenAppActive){
        [self.messagePoller begin];
    }
    
    [self checkMediaPermissions:config];
    return config;
}

-(void)updateConfig:(FreshchatConfig *)config andRegisterUser:(void(^)(NSError *error))completion{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    if (config) {
        [store setObject:config.stringsBundle forKey:HOTLINE_DEFAULTS_STRINGS_BUNDLE];
        [store setObject:config.appID forKey:HOTLINE_DEFAULTS_APP_ID];
        [store setObject:config.appKey forKey:HOTLINE_DEFAULTS_APP_KEY];
        [store setObject:config.domain forKey:HOTLINE_DEFAULTS_DOMAIN];
        [store setBoolValue:config.pictureMessagingEnabled forKey:HOTLINE_DEFAULTS_PICTURE_MESSAGE_ENABLED];
        //[store setBoolValue:config.voiceMessagingEnabled forKey:HOTLINE_DEFAULTS_VOICE_MESSAGE_ENABLED];
        [store setBoolValue:config.cameraCaptureEnabled forKey:HOTLINE_DEFAULTS_CAMERA_CAPTURE_ENABLED];
        [store setBoolValue:config.agentAvatarEnabled forKey:HOTLINE_DEFAULTS_AGENT_AVATAR_ENABLED];
        [store setBoolValue:config.notificationSoundEnabled forKey:HOTLINE_DEFAULTS_NOTIFICATION_SOUND_ENABLED];
        [store setBoolValue:config.showNotificationBanner forKey:HOTLINE_DEFAULTS_SHOW_NOTIFICATION_BANNER];
        [store setBoolValue:YES forKey:HOTLINE_DEFAULTS_SHOW_CHANNEL_THUMBNAIL];
        [store setObject:config.themeName forKey:HOTLINE_DEFAULTS_THEME_NAME];
        [[FCTheme sharedInstance]setThemeName:config.themeName];
    }
    
    if ([HLUser canRegisterUser]) {
        [HLUser registerUser:completion];
    }
    
}

-(void)checkMediaPermissions:(FreshchatConfig *)config{
    FDPlistManager *plistManager = [[FDPlistManager alloc] init];
    NSMutableString *message = [NSMutableString new];
    
//    if (config.voiceMessagingEnabled) {
//        if (![plistManager micUsageEnabled]) {
//            [message appendString:@"\nAdd key NSMicrophoneUsageDescription : To Enable Voice Message"];
//        }
//    }
    
    if (config.pictureMessagingEnabled) {
        if (![plistManager photoLibraryUsageEnabled]) {
            [message appendString:@"\nAdd key NSPhotoLibraryUsageDescription : To Enable access to Photo Library"];
        }
        
        if (![plistManager cameraUsageEnabled]) {
            [message appendString:@"\nAdd key NSCameraUsageDescription : To take Images from Camera"];
        }
    }
    
    if (message.length > 0) {
        NSString *info = @"Warning! Hotline SDK needs the following keys added to Info.plist for media access on iOS 10";
        ALog(@"\n\n** %@ ** \n %@ \n\n", info, message);
    }
}

-(void) registerAppNotificationListeners{
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(newSession:)
                                                 name: UIApplicationDidBecomeActiveNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleEnteredBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachable)
                                                 name:HOTLINE_NETWORK_REACHABLE object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(performPendingTasks)
                                                 name:HOTLINE_NOTIFICATION_PERFORM_PENDING_TASKS object:nil];
}

-(void)updateAppVersion{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    NSString *storedValue = [store objectForKey:HOTLINE_DEFAULTS_APP_VERSION];
    NSString *currentValue = [[[NSBundle bundleForClass:[self class]] infoDictionary]objectForKey:@"CFBundleShortVersionString"];
    if (storedValue && ![storedValue isEqualToString:currentValue]) {
        [KonotorCustomProperty createNewPropertyForKey:@"app_version" WithValue:currentValue isUserProperty:NO];
        [HLCoreServices uploadUnuploadedProperties];
    }
    [store setObject:currentValue forKey:HOTLINE_DEFAULTS_APP_VERSION];
}

-(void)updateSDKBuildNumber{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    NSString *storedValue = [store objectForKey:HOTLINE_DEFAULTS_SDK_BUILD_NUMBER];
    NSString *currentValue = HOTLINE_SDK_BUILD_NUMBER;
    if (![storedValue isEqualToString:currentValue]) {
        [[[HLCoreServices alloc]init]updateSDKBuildNumber:currentValue];
    }
}


-(void)cleanUpData:(void (^)())completion{
    KonotorDataManager *dataManager = [KonotorDataManager sharedInstance];
    NSDictionary *previousUser = [self getPreviousUserInfo];
    [dataManager deleteAllSolutions:^(NSError *error) {
        FDLog(@"All solutions deleted");
        [dataManager deleteAllIndices:^(NSError *error) {
            FDLog(@"Index cleared");
            [self resetUserWithCompletion:completion init:false andOldUser:previousUser];
        }];
    }];
}

-(NSDictionary *) getPreviousUserInfo{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    NSDictionary *previousUserInfo = nil;
    if( [HLUser isUserRegistered] &&
       [store objectForKey:HOTLINE_DEFAULTS_APP_ID] &&
       [store objectForKey:HOTLINE_DEFAULTS_APP_KEY] &&
       [store objectForKey:HOTLINE_DEFAULTS_DOMAIN] &&
       [FDUtilities currentUserAlias]){
        previousUserInfo =  @{ @"appId" : [store objectForKey:HOTLINE_DEFAULTS_APP_ID],
                               @"appKey" : [store objectForKey:HOTLINE_DEFAULTS_APP_KEY],
                               @"userAlias" :[FDUtilities currentUserAlias],
                               @"domain" : [store objectForKey:HOTLINE_DEFAULTS_DOMAIN]
                               };
    }
    return previousUserInfo;
}

-(BOOL)hasUpdatedConfig:(FreshchatConfig *)config{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    NSString *existingDomainName = [store objectForKey:HOTLINE_DEFAULTS_DOMAIN];
    NSString *existingAppID = [store objectForKey:HOTLINE_DEFAULTS_APP_ID];
    if ((existingDomainName && ![existingDomainName isEqualToString:@""])&&(existingAppID && ![existingAppID isEqualToString:@""])) {
        return (![existingDomainName isEqualToString:config.domain] || ![existingAppID isEqualToString:config.appID]) ? YES : NO;
    }else{
        //This is first launch, do not treat this as config update.
        FDLog(@"First launch");
        return NO;
    }
}

-(void) updateConversationBannerMessage:(NSString *) message{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    [store setObject:message forKey:HOTLINE_DEFAULTS_CONVERSATION_BANNER_MESSAGE];
    [FDLocalNotification post:HOTLINE_BANNER_MESSAGE_UPDATED];
}

-(void)setUser:(FreshchatUser *)user{
    [KonotorUser storeUserInfo:user];
    [HLCoreServices uploadUnuploadedProperties];
}


-(void)setUserProperties:(NSDictionary*)props{
    [[KonotorDataManager sharedInstance].mainObjectContext performBlock:^{
        NSDictionary *filteredProps = [FDUtilities filterValidUserPropEntries:props];
        if(filteredProps){
            for(NSString *key in filteredProps){
                NSString *value = props[key];
                [KonotorCustomProperty createNewPropertyForKey:key WithValue:value isUserProperty:NO];
            }
        }
        [HLCoreServices uploadUnuploadedProperties];
    }];
}

-(void)updateUserLocaleProperties:(NSString *)locale {
    [[KonotorDataManager sharedInstance].mainObjectContext performBlock:^{
        [KonotorCustomProperty createNewPropertyForKey:LOCALE WithValue:locale isUserProperty:YES];
        [HLCoreServices uploadUnuploadedProperties];
    }];
}



-(void)setUserPropertyforKey:(NSString *) key withValue:(NSString *)value{
    if (key && value) {
        [self setUserProperties:@{ key : value}];
    }
    else {
        ALog(@"Null property %@ provided. Not updated", key ? @"value" : @"key" );
    }
}

-(void)registerDeviceToken{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    if([HLUser isUserRegistered]){
        BOOL isDeviceTokenRegistered = [store boolValueForKey:HOTLINE_DEFAULTS_IS_DEVICE_TOKEN_REGISTERED];
        if (!isDeviceTokenRegistered) {
            NSString *userAlias = [FDUtilities currentUserAlias];
            NSString *token = [store objectForKey:HOTLINE_DEFAULTS_PUSH_TOKEN];
            [[[HLCoreServices alloc]init] registerAppWithToken:token forUser:userAlias handler:nil];
        }
    }
    else {
        FDLog(@"Not updating device token : Register user first");
    }
}

/*  This function is called during every launch &
 when the SDK's app is transitioned from background to foreground  */

-(void)newSession:(NSNotification *)notification{
    if([FDUtilities hasInitConfig]) {
        if(self.config.pollWhenAppActive){
            [self.messagePoller begin];
        }
        [FDUtilities initiatePendingTasks];
    }
}

-(void)handleEnteredBackground:(NSNotification *)notification{
    //save last message session
    [self.messagePoller end];
    [self updateSessionInterval];
}

- (void) updateSessionInterval{
    if([HLUser isUserRegistered]){
        [HLUserDefaults setObject:[NSDate date] forKey:FRESHCHAT_DEFAULTS_SESSION_UPDATED_TIME];
    }
}

-(void) updateLocaleMeta {
    if([FDLocaleUtil hadLocaleChange]) {
        [[FDSecureStore sharedInstance] removeObjectWithKey:HOTLINE_DEFAULTS_SOLUTIONS_LAST_UPDATED_INTERVAL_TIME];
        NSString *localLocale = [FDLocaleUtil getLocalLocale];
        [[Hotline sharedInstance] updateUserLocaleProperties:localLocale];
    }
}

-(void)performPendingTasks{
    FDLog(@"Performing pending tasks");
    if ([HLUser canRegisterUser]) {
        [HLUser registerUser:nil];
    }
    if([FDUtilities hasInitConfig]) {
        if([FDUtilities canMakeDAUCall]){
            [HLCoreServices performDAUCall];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if([HLUser isUserRegistered]){
                [HLCoreServices performHeartbeatCall];
                if([FDUtilities canMakeSessionCall]){
                    [self updateSessionInterval];
                    [HLCoreServices performSessionCall];
                }
                [self registerDeviceToken];
                [self updateAppVersion];
                [self updateAdId];
                [self updateSDKBuildNumber];
                [HLMessageServices fetchChannelsAndMessagesWithFetchType:InitFetch
                                                                 source : Init
                                                              andHandler:nil];
                [HLCoreServices uploadUnuploadedProperties];
                [Message uploadAllUnuploadedMessages];
                [HLMessageServices uploadUnuploadedCSAT];
            }
            [self updateLocaleMeta];
            [[[FDSolutionUpdater alloc]init] fetch];
            [self markPreviousUserUninstalledIfPresent];
        });
    }
}

-(void) updateAdId{
    FDSecureStore *secureStore = [FDSecureStore sharedInstance];
    NSString *storedAdId = [secureStore objectForKey:HOTLINE_DEFAULTS_ADID];
    NSString *adId = [FDUtilities getAdID];
    if(adId && adId.length > 0 && ![adId isEqualToString:storedAdId]){
        [secureStore setObject:adId forKey:HOTLINE_DEFAULTS_ADID];
        [KonotorCustomProperty createNewPropertyForKey:@"adId" WithValue:adId isUserProperty:YES];
    }
}

#pragma mark - Route controllers

-(void)showFAQs:(UIViewController *)controller{
    [self showFAQs:controller withOptions:[FAQOptions new]];
}

-(void)showConversations:(UIViewController *)controller{
    [self showConversations:controller withOptions:[ConversationOptions new]];
}

-(void)showFAQs:(UIViewController *)controller withOptions:(FAQOptions *)options{
    [HLControllerUtils presentOn:controller option:options];
}

- (void) showConversations:(UIViewController *)controller withOptions :(ConversationOptions *)options {
    [HLControllerUtils presentOn:controller option:options];
}

-(UIViewController*) getFAQsControllerForEmbed{
    return [self getFAQsControllerForEmbedWithOptions:[FAQOptions new]];
}

-(UIViewController*) getConversationsControllerForEmbed{
    return [self getConversationsControllerForEmbedWithOptions:[ConversationOptions new]];
}

-(UIViewController*) getConversationsControllerForEmbedWithOptions:(ConversationOptions *) convOptions{
    return [HLControllerUtils getEmbedded:convOptions];
}

-(UIViewController*) getFAQsControllerForEmbedWithOptions:(FAQOptions *) faqOptions{
    return [HLControllerUtils getEmbedded:faqOptions];
}

#pragma mark Push notifications

-(void)setPushRegistrationToken:(NSData *)deviceToken {
    NSString *deviceTokenString = [[[deviceToken.description stringByReplacingOccurrencesOfString:@"<"withString:@""] stringByReplacingOccurrencesOfString:@">"withString:@""] stringByReplacingOccurrencesOfString:@" "withString:@""];
    if ([self isDeviceTokenUpdated:deviceTokenString]) {
        [self storeDeviceToken:deviceTokenString];
        [self registerDeviceToken];
    }
}

-(void) storeDeviceToken:(NSString *) deviceTokenString{
    if (deviceTokenString) {
        FDSecureStore *store = [FDSecureStore sharedInstance];
        [store setObject:deviceTokenString forKey:HOTLINE_DEFAULTS_PUSH_TOKEN];
        [store setBoolValue:NO forKey:HOTLINE_DEFAULTS_IS_DEVICE_TOKEN_REGISTERED];
    }
}

-(BOOL)isDeviceTokenUpdated:(NSString *)newToken{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    if (newToken && ![newToken isEqualToString:@""]) {
        NSString* storedDeviceToken = [store objectForKey:HOTLINE_DEFAULTS_PUSH_TOKEN];
        return (storedDeviceToken == nil || ![storedDeviceToken isEqualToString:newToken]);
    }else{
        return NO;
    }
}

-(BOOL)isFreshchatNotification:(NSDictionary *)info{
    @try {
        return [HLNotificationHandler isFreshchatNotification:info];
    } @catch (NSException *exception) {
        FDMemLogger *logger = [FDMemLogger new];
        [logger addMessage:exception.debugDescription withMethodName:NSStringFromSelector(_cmd)];
        [logger addErrorInfo:info];
        [logger upload];
    }
    return NO; // Return a valid value to avoid inconsistency
}

-(void)handleRemoteNotification:(NSDictionary *)info andAppstate:(UIApplicationState)appState{
    @try {
        if(![self isFreshchatNotification:info]){
            return;
        }
        self.notificationHandler = [[HLNotificationHandler alloc]init];
        [self.notificationHandler handleNotification:info appState:appState];
    } @catch (NSException *exception) {
        FDMemLogger *logger = [FDMemLogger new];
        [logger addMessage:exception.debugDescription withMethodName:NSStringFromSelector(_cmd)];
        [logger addErrorInfo:info];
        [logger upload];
    }
}

-(void)resetUser{
    [self resetUserWithCompletion:nil init:true andOldUser:nil];
}

static BOOL CLEAR_DATA_IN_PROGRESS = NO;

-(void)resetUserWithCompletion:(void (^)())completion init:(BOOL)doInit andOldUser:(NSDictionary*) previousUser {
    if (CLEAR_DATA_IN_PROGRESS == NO) {
        CLEAR_DATA_IN_PROGRESS = YES;
        [self processClearUserData:^{
            CLEAR_DATA_IN_PROGRESS = NO;
            if(completion){
                completion();
            }
            ALog(@"Clear user data completed");
        } init:doInit andOldUser:previousUser];
    }
    else {
        ALog(@"Clear user data already in progress");
    }
}

-(void)processClearUserData:(void (^)())completion init:(BOOL)doInit andOldUser:(NSDictionary*) previousUser{
    FDSecureStore *store = [FDSecureStore sharedInstance];
    FreshchatConfig *config = [[FreshchatConfig alloc] initWithAppID:[store objectForKey:HOTLINE_DEFAULTS_APP_ID]
                                                       andAppKey:[store objectForKey:HOTLINE_DEFAULTS_APP_KEY]];
    if([store objectForKey:HOTLINE_DEFAULTS_DOMAIN]){
        config.domain = [store objectForKey:HOTLINE_DEFAULTS_DOMAIN];
    }
    config.agentAvatarEnabled =[store boolValueForKey:HOTLINE_DEFAULTS_AGENT_AVATAR_ENABLED];
    //config.voiceMessagingEnabled = [store boolValueForKey:HOTLINE_DEFAULTS_VOICE_MESSAGE_ENABLED];
    config.pictureMessagingEnabled = [store boolValueForKey:HOTLINE_DEFAULTS_PICTURE_MESSAGE_ENABLED];
    config.cameraCaptureEnabled = [store boolValueForKey:HOTLINE_DEFAULTS_CAMERA_CAPTURE_ENABLED];
    config.showNotificationBanner = [store boolValueForKey:HOTLINE_DEFAULTS_SHOW_NOTIFICATION_BANNER];
    if([store objectForKey:HOTLINE_DEFAULTS_THEME_NAME]){
        config.themeName = [store objectForKey:HOTLINE_DEFAULTS_THEME_NAME];
    } else {
        config.themeName = FD_DEFAULT_THEME_NAME;
    }
    
    if(!previousUser) {
        previousUser = [self getPreviousUserInfo];
    }
    
    NSString *deviceToken = [store objectForKey:HOTLINE_DEFAULTS_PUSH_TOKEN];
    
    
    [[FreshchatUser sharedInstance]resetUser]; // This clear Sercure Store data as well.
    
    //Clear secure store
    [[FDSecureStore sharedInstance]clearStoreData];
    [[FDSecureStore persistedStoreInstance]clearStoreData];
    
    [HLUserDefaults clearUserDefaults];
    
    if(previousUser) {
        [self storePreviousUser:previousUser inStore:store];
    }
    
    [[KonotorDataManager sharedInstance] cleanUpUser:^(NSError *error) {
        if(doInit){
            [self initWithConfig:config completion:completion];
            if([FDUtilities canMakeDAUCall]){
                [HLCoreServices performDAUCall];
            }
        }else{
            if (completion) {
                completion();
            }
        }
        if (deviceToken) {
            [self storeDeviceToken:deviceToken];
            if (completion) {
                completion();
            }
        }
    }];
}

-(void)resetUserWithCompletion:(void (^)())completion{
    [self resetUserWithCompletion:completion init:true andOldUser:nil];
}

-(void)unreadCountWithCompletion:(void (^)(NSInteger count))completion{
    if (completion) {
        [HLMessageServices fetchChannelsAndMessagesWithFetchType:OffScreenPollFetch
                                                          source:UnreadCount
                                                      andHandler:^(NSError *error) {
                                                          [FDUtilities unreadCountInternalHandler:^(NSInteger count) {
                                                              completion(count);
                                                          }];
                                                      }];
    }
}

-(void)unreadCountForTags:(NSArray *)tags withCompletion:(void(^)(NSInteger count))completion{
    __block int count=0;
    if (completion) {
        [HLMessageServices fetchChannelsAndMessagesWithFetchType:OffScreenPollFetch source:UnreadCount andHandler:^(NSError *error) {
            if(error) {
                completion(count);
                return;
            }
            else {
                [[HLTagManager sharedInstance] getChannelsForTags:tags
                                                        inContext:[KonotorDataManager sharedInstance].mainObjectContext
                                                   withCompletion:^(NSArray<HLChannel *> * channels) {
                                                       for(HLChannel *channel in channels){
                                                           count += [channel unreadCount];
                                                       }
                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                           completion(count);
                                                       });
                                                   }];
            }
        }];
    }
}

-(void) sendMessage:(FreshchatMessage *)messageObject{
    if(messageObject.message.length == 0 || messageObject.tag.length == 0){
        return;
    }
    NSManagedObjectContext *mainContext = [[KonotorDataManager sharedInstance] mainObjectContext];
    [mainContext performBlock:^{
        [[HLTagManager sharedInstance] getChannelsForTags:@[messageObject.tag] inContext:mainContext withCompletion:^(NSArray<HLChannel *> *channels){
            HLChannel *channel;
            if(channels.count >=1){
                channel = [channels firstObject];  // 1 will have the match , if more than one. it is ordered by pos
            }
            if(!channel){
                channel = [HLChannel getDefaultChannelInContext:mainContext];
            }
            if(channel){
                KonotorConversation *conversation;
                NSSet *conversations = channel.conversations;
                if(conversations && [conversations count] > 0 ){
                    conversation = [conversations anyObject];
                }
                [Konotor uploadTextFeedback:messageObject.message onConversation:conversation onChannel:channel];
            }
        }];
    }];
}

- (NSString *)validateDomain:(NSString*)domain{
    return [FDStringUtil replaceInString:trimString(domain) usingRegex:@"^http[s]?:\\/\\/" replaceWith:@""];
}

-(void)storePreviousUser:(NSDictionary *) previousUserInfo inStore:(FDSecureStore *)secureStore{
    [secureStore setObject:previousUserInfo forKey:HOTLINE_DEFAULTS_OLD_USER_INFO];
}

-(void)markPreviousUserUninstalledIfPresent{
    static BOOL inProgress = false; // performPendingTasks can be called twice so sequence
    FDSecureStore *store = [FDSecureStore sharedInstance];
    NSDictionary *previousUserInfo = [store objectForKey:HOTLINE_DEFAULTS_OLD_USER_INFO];
    if(previousUserInfo && !inProgress){
        inProgress = true;
        [HLCoreServices trackUninstallForUser:previousUserInfo withCompletion:^(NSError *error) {
            if(!error){
                [store removeObjectWithKey:HOTLINE_DEFAULTS_OLD_USER_INFO];
                inProgress = false;
            }
        }];
    }
}

-(void)dismissHotlineViewInController:(UIViewController *) controller
                       withCompletion: (void(^)())completion  {
    void (^clearHLControllers)() = ^void() {
        for(UIViewController *tempVC in controller.childViewControllers){
            if([tempVC isKindOfClass:[HLContainerController class]]){
                [tempVC dismissViewControllerAnimated:NO completion:completion];
            }
        }
    };
    if(controller.presentedViewController){
        [self dismissHotlineViewInController:controller.presentedViewController
                              withCompletion:clearHLControllers];
    }
    else {
        clearHLControllers();
    }
}

-(void) dismissFreshchatViews {
    UIViewController *rootController = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    [self dismissHotlineViewInController:rootController withCompletion:nil];
}

@end
