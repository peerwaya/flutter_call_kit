#import "FlutterCallKitPlugin.h"

#import <AVFoundation/AVAudioSession.h>

#ifdef DEBUG
static int const OUTGOING_CALL_WAKEUP_DELAY = 10;
#else
static int const OUTGOING_CALL_WAKEUP_DELAY = 5;
#endif

static NSString *const kHandleStartCallNotification = @"handleStartCallNotification";
static NSString *const kDidReceiveStartCallAction = @"didReceiveStartCallAction";
static NSString *const kPerformAnswerCallAction = @"performAnswerCallAction";
static NSString *const kPerformEndCallAction = @"performEndCallAction";
static NSString *const kDidActivateAudioSession = @"didActivateAudioSession";
static NSString *const kDidDeactivateAudioSession = @"didDeactivateAudioSession";
static NSString *const kDidDisplayIncomingCall = @"didDisplayIncomingCall";
static NSString *const kDidPerformSetMutedCallAction = @"didPerformSetMutedCallAction";
static NSString *const kDidPerformDTMFAction = @"didPerformDTMFAction";
static NSString *const kDidToggleHoldAction = @"didToggleHoldAction";

static NSString *const kProviderReset = @"onProviderReset";

NSString *const kIncomingCallNotification = @"incomingCallNotification";

static FlutterError *getFlutterError(NSError *error) {
    if (error == nil) return nil;
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %ld", error.code]
                               message:error.domain
                               details:error.localizedDescription];
}

@implementation FlutterCallKitPlugin {
    FlutterMethodChannel* _channel;
    NSOperatingSystemVersion _version;
    BOOL _isConfigured;
    NSDictionary *_incomingCallNotification;
    NSDictionary *_startCallNotification;
}

static CXProvider* sharedProvider;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterCallKitPlugin* instance = [[FlutterCallKitPlugin alloc] initWithRegistrar:registrar messenger:[registrar messenger]];
    [registrar addApplicationDelegate:instance];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
                        messenger:(NSObject<FlutterBinaryMessenger>*)messenger{
    self = [super init];
    if (self) {
        _channel = [FlutterMethodChannel
                    methodChannelWithName:@"com.peerwaya/flutter_callkit_plugin"
                    binaryMessenger:[registrar messenger]];
        [registrar addMethodCallDelegate:self channel:_channel];
        _isConfigured = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleNewIncomingCall:)
                                                     name:kIncomingCallNotification
                                                   object:nil];
    }
    return self;
}

+ (void)initCallKitProvider {
    if (sharedProvider == nil) {
        NSDictionary *settings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"FlutterCallKitPluginSettings"];
        sharedProvider = [[CXProvider alloc] initWithConfiguration:[FlutterCallKitPlugin getProviderConfiguration:settings]];
        NSLog(@"[FlutterCallKit][initCallKitProvider] sharedProvider initialized with %@", settings);
    }
}

- (void)dealloc
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKit][dealloc]");
#endif
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (self.callKitProvider != nil) {
        [self.callKitProvider invalidate];
    }
    sharedProvider = nil;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString *method = call.method;
    if ([@"configure" isEqualToString:method]) {
        _isConfigured = YES;
        [self configure:call.arguments result:result];
    }else if ([@"checkIfBusy" isEqualToString:method]) {
#ifdef DEBUG
        NSLog(@"[FlutterCallKitPlugin][checkIfBusy]");
#endif
        result(@(self.callKitCallController.callObserver.calls.count > 0));
    }else if ([@"checkSpeaker" isEqualToString:method]) {
#ifdef DEBUG
        NSLog(@"[FlutterCallKitPlugin][checkSpeaker]");
#endif
        NSString *output = [AVAudioSession sharedInstance].currentRoute.outputs.count > 0 ? [AVAudioSession sharedInstance].currentRoute.outputs[0].portType : nil;
        result(@([output isEqualToString:@"Speaker"]));
    }else if ([@"displayIncomingCall" isEqualToString:method]) {
        [self displayIncomingCall:call.arguments result:result];
    }else if ([@"startCall" isEqualToString:method]) {
        [self startCall:call.arguments result:result];
    }else if ([@"reportConnectingOutgoingCallWithUUID" isEqualToString:method]) {
        [self reportConnectingOutgoingCallWithUUID:(NSString *)call.arguments result:result];
    }else if ([@"reportConnectedOutgoingCallWithUUID" isEqualToString:method]) {
        [self reportConnectedOutgoingCallWithUUID:(NSString *)call.arguments result:result];
    }else if ([@"reportEndCall" isEqualToString:method]) {
        [self reportEndCall:call.arguments result:result];
    }else if ([@"endCall" isEqualToString:method]) {
        [self endCall:(NSString *)call.arguments result:result];
    }else if ([@"endAllCalls" isEqualToString:method]) {
        [self endAllCalls:result];
    }else if ([@"setMutedCall" isEqualToString:method]) {
        [self setMutedCall:call.arguments result:result];
    }else if ([@"updateDisplay" isEqualToString:method]) {
        [self updateDisplay:call.arguments result:result];
    }else if ([@"setOnHold" isEqualToString:method]) {
        [self setOnHold:call.arguments result:result];
    }else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)configure:(NSDictionary *)options result:(FlutterResult)result
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][setup] options = %@", options);
#endif
    _version = [[[NSProcessInfo alloc] init] operatingSystemVersion];
    self.callKitCallController = [[CXCallController alloc] init];
    NSDictionary *settings = [[NSMutableDictionary alloc] initWithDictionary:options];
    // Store settings in NSUserDefault
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:@"FlutterCallKitPluginSettings"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [FlutterCallKitPlugin initCallKitProvider];
    
    self.callKitProvider = sharedProvider;
    [self.callKitProvider setDelegate:self queue:nil];
    if (_incomingCallNotification != nil) {
        [_channel invokeMethod:kDidDisplayIncomingCall arguments:_incomingCallNotification];
        _incomingCallNotification = nil;
    }
    if (_startCallNotification != nil) {
        [_channel invokeMethod:kDidDisplayIncomingCall arguments:_startCallNotification];
        _startCallNotification = nil;
    }
    result(nil);
}

#pragma mark - CXCallController call actions
- (void)displayIncomingCall:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSString* handle = arguments[@"handle"];
    NSString* handleType = arguments[@"handleType"];
    NSNumber* video = arguments[@"video"];
    NSString* localizedCallerName = arguments[@"localizedCallerName"];
    [FlutterCallKitPlugin reportNewIncomingCall:uuidString handle:handle handleType:handleType hasVideo:[video boolValue] localizedCallerName:localizedCallerName fromPushKit:NO];
    result(nil);
}

- (void)startCall:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSString* handle = arguments[@"handle"];
    NSString* handleType = arguments[@"handleType"];
    NSString* contactIdentifier = arguments[@"contactIdentifier"];
    NSNumber* video = arguments[@"video"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][startCall] uuid = %@", uuidString);
#endif
    int _handleType = [FlutterCallKitPlugin getHandleType:handleType];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    CXHandle *callHandle = [[CXHandle alloc] initWithType:_handleType value:handle];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:callHandle];
    [startCallAction setVideo:[video boolValue]];
    [startCallAction setContactIdentifier:contactIdentifier];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
    
    [self requestTransaction:transaction result:result];
}

- (void)endCall:(NSString *)uuidString result:(FlutterResult)result
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][endCall] uuid = %@", uuidString);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];
    
    [self requestTransaction:transaction result:result];
}

- (void)endAllCalls:(FlutterResult)result
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][endAllCalls] calls = %@", self.callKitCallController.callObserver.calls);
#endif
    for (CXCall *call in self.callKitCallController.callObserver.calls) {
        CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:call.UUID];
        CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];
        [self requestTransaction:transaction result:nil];
    }
    result(nil);
}

- (void)setOnHold:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSNumber* hold = arguments[@"hold"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][setOnHold] uuid = %@, shouldHold = %d", uuidString, [hold boolValue]);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    CXSetHeldCallAction *setHeldCallAction = [[CXSetHeldCallAction alloc] initWithCallUUID:uuid onHold:[hold boolValue]];
    CXTransaction *transaction = [[CXTransaction alloc] init];
    [transaction addAction:setHeldCallAction];
    
    [self requestTransaction:transaction result:result];
}

- (void)reportConnectingOutgoingCallWithUUID:(NSString *)uuidString result:(FlutterResult)result
{
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    [self.callKitProvider reportOutgoingCallWithUUID:uuid startedConnectingAtDate:[NSDate date]];
    result(nil);
}

- (void)reportConnectedOutgoingCallWithUUID:(NSString *)uuidString result:(FlutterResult)result
{
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    [self.callKitProvider reportOutgoingCallWithUUID:uuid connectedAtDate:[NSDate date]];
    result(nil);
}

- (void)reportEndCall:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSNumber* reason = arguments[@"reason"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][reportEndCallWithUUID] uuid = %@ reason = %d", uuidString, [reason intValue]);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    switch ([reason intValue]) {
        case CXCallEndedReasonFailed:
            [self.callKitProvider reportCallWithUUID:uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonFailed];
            break;
        case CXCallEndedReasonRemoteEnded:
            [self.callKitProvider reportCallWithUUID:uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonRemoteEnded];
            break;
        case CXCallEndedReasonUnanswered:
            [self.callKitProvider reportCallWithUUID:uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonUnanswered];
            break;
        case CXCallEndedReasonAnsweredElsewhere:
            [self.callKitProvider reportCallWithUUID:uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonUnanswered];
            break;
        case CXCallEndedReasonDeclinedElsewhere:
            [self.callKitProvider reportCallWithUUID:uuid endedAtDate:[NSDate date] reason:CXCallEndedReasonUnanswered];
            break;
        default:
            break;
    }
    result(nil);
}

- (void)updateDisplay:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSString* displayName = arguments[@"displayName"];
    NSString* handle = arguments[@"handle"];
    NSString* handleType = arguments[@"handleType"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][updateDisplay] uuid = %@ displayName = %@ handle = %@", uuidString, displayName, handle);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    int _handleType = [FlutterCallKitPlugin getHandleType:handleType];
    CXHandle *callHandle = [[CXHandle alloc] initWithType:_handleType value:handle];
    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.localizedCallerName = displayName;
    callUpdate.remoteHandle = callHandle;
    [self.callKitProvider reportCallWithUUID:uuid updated:callUpdate];
    result(nil);
}

- (void)setMutedCall:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSNumber* muted = arguments[@"muted"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][setMutedCall] muted = %i", [muted boolValue]);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    CXSetMutedCallAction *setMutedAction = [[CXSetMutedCallAction alloc] initWithCallUUID:uuid muted:[muted boolValue]];
    CXTransaction *transaction = [[CXTransaction alloc] init];
    [transaction addAction:setMutedAction];
    
    [self requestTransaction:transaction result:result];
}

- (void)sendDTMF:(NSDictionary *)arguments result:(FlutterResult)result
{
    NSString* uuidString = arguments[@"uuid"];
    NSString* key = arguments[@"key"];
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][sendDTMF] key = %@", key);
#endif
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    CXPlayDTMFCallAction *dtmfAction = [[CXPlayDTMFCallAction alloc] initWithCallUUID:uuid digits:key type:CXPlayDTMFCallActionTypeHardPause];
    CXTransaction *transaction = [[CXTransaction alloc] init];
    [transaction addAction:dtmfAction];
    
    [self requestTransaction:transaction result:result];
}

- (void)requestTransaction:(CXTransaction *)transaction result:(FlutterResult)result
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][requestTransaction] transaction = %@", transaction);
#endif
    if (self.callKitCallController == nil) {
        self.callKitCallController = [[CXCallController alloc] init];
    }
    [self.callKitCallController requestTransaction:transaction completion:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"[FlutterCallKitPlugin][requestTransaction] Error requesting transaction (%@): (%@)", transaction.actions, error);
            if (result) {
                result(getFlutterError(error));
            }
        } else {
            NSLog(@"[FlutterCallKitPlugin][requestTransaction] Requested transaction successfully");
            
            // CXStartCallAction
            if ([[transaction.actions firstObject] isKindOfClass:[CXStartCallAction class]]) {
                CXStartCallAction *startCallAction = [transaction.actions firstObject];
                CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
                callUpdate.remoteHandle = startCallAction.handle;
                callUpdate.hasVideo = startCallAction.video;
                callUpdate.localizedCallerName = startCallAction.contactIdentifier;
                callUpdate.supportsDTMF = YES;
                callUpdate.supportsHolding = YES;
                callUpdate.supportsGrouping = YES;
                callUpdate.supportsUngrouping = YES;
                [self.callKitProvider reportCallWithUUID:startCallAction.callUUID updated:callUpdate];
            }
            if (result) {
                result(nil);
            }
        }
    }];
}

- (BOOL)lessThanIos10_2
{
    if (_version.majorVersion < 10) {
        return YES;
    } else if (_version.majorVersion > 10) {
        return NO;
    } else {
        return _version.minorVersion < 2;
    }
}

+ (int)getHandleType:(NSString *)handleType
{
    int _handleType;
    if ([handleType isEqualToString:@"generic"]) {
        _handleType = CXHandleTypeGeneric;
    } else if ([handleType isEqualToString:@"number"]) {
        _handleType = CXHandleTypePhoneNumber;
    } else if ([handleType isEqualToString:@"email"]) {
        _handleType = CXHandleTypeEmailAddress;
    } else {
        _handleType = CXHandleTypeGeneric;
    }
    return _handleType;
}

+ (CXProviderConfiguration *)getProviderConfiguration:(NSDictionary*)settings
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][getProviderConfiguration]");
#endif
    CXProviderConfiguration *providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:settings[@"appName"]];
    providerConfiguration.supportsVideo = YES;
    providerConfiguration.maximumCallGroups = 3;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    providerConfiguration.supportedHandleTypes = [NSSet setWithObjects:[NSNumber numberWithInteger:CXHandleTypeGeneric],[NSNumber numberWithInteger:CXHandleTypePhoneNumber], [NSNumber numberWithInteger:CXHandleTypeEmailAddress], nil];
    if (@available(iOS 11.0, *)) {
        providerConfiguration.includesCallsInRecents = [settings[@"includesCallsInRecents"] boolValue];
    }
    if (settings[@"supportsVideo"]) {
        providerConfiguration.supportsVideo = [settings[@"supportsVideo"] boolValue];
    }
    if (settings[@"maximumCallGroups"]) {
        providerConfiguration.maximumCallGroups = [settings[@"maximumCallGroups"] integerValue];
    }
    if (settings[@"maximumCallsPerCallGroup"]) {
        providerConfiguration.maximumCallsPerCallGroup = [settings[@"maximumCallsPerCallGroup"] integerValue];
    }
    if (settings[@"imageName"]) {
        providerConfiguration.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:settings[@"imageName"]]);
    }
    if (settings[@"ringtoneSound"]) {
        providerConfiguration.ringtoneSound = settings[@"ringtoneSound"];
    }
    return providerConfiguration;
}

- (void)configureAudioSession
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][configureAudioSession] Activating audio session");
#endif

    AVAudioSession* audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:nil];

    [audioSession setMode:AVAudioSessionModeVoiceChat error:nil];

    double sampleRate = 44100.0;
    [audioSession setPreferredSampleRate:sampleRate error:nil];

    NSTimeInterval bufferDuration = .005;
    [audioSession setPreferredIOBufferDuration:bufferDuration error:nil];
    [audioSession setActive:TRUE error:nil];
}

#pragma mark - AppDelegate
- (BOOL)application:(UIApplication *)application
continueUserActivity:(NSUserActivity *)userActivity
 restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *restorableObjects))restorationHandler
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][application:continueUserActivity]");
#endif
    INInteraction *interaction = userActivity.interaction;
    INPerson *contact;
    NSString *handle;
    BOOL isAudioCall;
    BOOL isVideoCall;

    //HACK TO AVOID XCODE 10 COMPILE CRASH
    //REMOVE ON NEXT MAJOR RELEASE OF RNCALLKIT
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    //XCode 11
    // iOS 13 returns an INStartCallIntent userActivity type
    if (@available(iOS 13, *)) {
        INStartCallIntent *intent = (INStartCallIntent*)interaction.intent;
        if ([intent respondsToSelector:@selector(callCapability)]) {
            isAudioCall = intent.callCapability == INCallCapabilityAudioCall;
            isVideoCall = intent.callCapability == INCallCapabilityVideoCall;
        } else {
            isAudioCall = [userActivity.activityType isEqualToString:INStartAudioCallIntentIdentifier];
            isVideoCall = [userActivity.activityType isEqualToString:INStartVideoCallIntentIdentifier];
        }
    } else {
#endif
        //XCode 10 and below
        isAudioCall = [userActivity.activityType isEqualToString:INStartAudioCallIntentIdentifier];
        isVideoCall = [userActivity.activityType isEqualToString:INStartVideoCallIntentIdentifier];
        //HACK TO AVOID XCODE 10 COMPILE CRASH
        //REMOVE ON NEXT MAJOR RELEASE OF RNCALLKIT
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    }
#endif
    
    if (isAudioCall) {
        INStartAudioCallIntent *startAudioCallIntent = (INStartAudioCallIntent *)interaction.intent;
        contact = [startAudioCallIntent.contacts firstObject];
    } else if (isVideoCall) {
        INStartVideoCallIntent *startVideoCallIntent = (INStartVideoCallIntent *)interaction.intent;
        contact = [startVideoCallIntent.contacts firstObject];
    }
    
    if (contact != nil) {
        handle = contact.personHandle.value;
    }
    
    if (handle != nil && handle.length > 0 ){
        NSDictionary *userInfo = @{
                                   @"handle": handle,
                                   @"video": @(isVideoCall)
                                   };
        if (_isConfigured) {
            [_channel invokeMethod:kHandleStartCallNotification arguments:userInfo];
        } else {
            _startCallNotification = userInfo;
        }
        return YES;
    }
    return NO;
}

+ (void)reportNewIncomingCall:(NSString *)uuidString
                       handle:(NSString *)handle
                   handleType:(NSString *)handleType
                     hasVideo:(BOOL)hasVideo
          localizedCallerName:(NSString * _Nullable)localizedCallerName
                  fromPushKit:(BOOL)fromPushKit
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][reportNewIncomingCall] uuidString = %@, handle = %@, handleType = %@, hasVideo = %@, localizedCallerName = %@, fromPushKit = %@", uuidString, handle, handleType, @(hasVideo), localizedCallerName, @(fromPushKit) );
#endif
    int _handleType = [FlutterCallKitPlugin getHandleType:handleType];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
    NSLog(@"[FlutterCallKitPlugin][reportNewIncomingCall] uuid = %@", uuid );
    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = [[CXHandle alloc] initWithType:_handleType value:handle];
    callUpdate.supportsDTMF = YES;
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = YES;
    callUpdate.supportsUngrouping = YES;
    callUpdate.hasVideo = hasVideo;
    callUpdate.localizedCallerName = localizedCallerName;
    
    [FlutterCallKitPlugin initCallKitProvider];
    [sharedProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError * _Nullable error) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kIncomingCallNotification
                                                            object:self
                                                          userInfo:@{ @"error": error ? error.localizedDescription : [NSNull null], @"callUUID": uuidString, @"handle": handle, @"localizedCallerName": localizedCallerName, @"fromPushKit": @(fromPushKit)}];
    }];
}

- (void)handleNewIncomingCall:(NSNotification *)notification
{
    #ifdef DEBUG
        NSLog(@"[FlutterCallKitPlugin] handleNewIncomingCall notification.userInfo = %@", notification.userInfo);
    #endif
    if (_isConfigured) {
        [_channel invokeMethod:kDidDisplayIncomingCall arguments:notification.userInfo];
    } else {
        _incomingCallNotification = notification.userInfo;
    }
    NSDictionary *userInfo = (NSDictionary *)notification.userInfo;
    if (userInfo[@"error"] == nil) {
        // Workaround per https://forums.developer.apple.com/message/169511
        if ([self lessThanIos10_2]) {
            [self configureAudioSession];
        }
    }
}

#pragma mark - CXProviderDelegate

- (void)providerDidReset:(CXProvider *)provider{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][providerDidReset]");
#endif
    //this means something big changed, so tell the JS. The JS should
    //probably respond by hanging up all calls.
    [_channel invokeMethod:kProviderReset arguments:nil];
}

// Starting outgoing call
- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performStartCallAction]");
#endif
    //do this first, audio sessions are flakey
    [self configureAudioSession];
    //tell the JS to actually make the call
    [_channel invokeMethod:kDidReceiveStartCallAction arguments:@{ @"callUUID": [action.callUUID.UUIDString lowercaseString], @"handle": action.handle.value }];
    [action fulfill];
}

// Answering incoming call
- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performAnswerCallAction]");
#endif
    [self configureAudioSession];
    [_channel invokeMethod:kPerformAnswerCallAction arguments:@{ @"callUUID": [action.callUUID.UUIDString lowercaseString] }];
    [action fulfill];
}

// Ending incoming call
- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performEndCallAction]");
#endif
    [_channel invokeMethod:kPerformEndCallAction arguments:@{ @"callUUID": [action.callUUID.UUIDString lowercaseString] }];
    [action fulfill];
}

-(void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performSetHeldCallAction]");
#endif
    [_channel invokeMethod:kDidToggleHoldAction arguments:@{ @"hold": @(action.onHold), @"callUUID": [action.callUUID.UUIDString lowercaseString] }];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performPlayDTMFCallAction:(CXPlayDTMFCallAction *)action {
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performPlayDTMFCallAction]");
#endif
    [_channel invokeMethod:kDidPerformDTMFAction arguments:@{ @"digits": action.digits, @"callUUID": [action.callUUID.UUIDString lowercaseString] }];
    [action fulfill];
}

-(void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:performSetMutedCallAction]");
#endif
    [_channel invokeMethod:kDidPerformSetMutedCallAction arguments:@{ @"muted": @(action.muted), @"callUUID": [action.callUUID.UUIDString lowercaseString] }];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:timedOutPerformingAction]");
#endif
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:didActivateAudioSession]");
#endif
    NSDictionary *userInfo
    = @{
        AVAudioSessionInterruptionTypeKey: [NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded],
        AVAudioSessionInterruptionOptionKey: [NSNumber numberWithInt:AVAudioSessionInterruptionOptionShouldResume]
        };
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAudioSessionInterruptionNotification object:nil userInfo:userInfo];
    
    [self configureAudioSession];
    [_channel invokeMethod:kDidActivateAudioSession arguments:nil];
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession
{
#ifdef DEBUG
    NSLog(@"[FlutterCallKitPlugin][CXProviderDelegate][provider:didDeactivateAudioSession]");
#endif
    [_channel invokeMethod:kDidDeactivateAudioSession arguments:nil];
}
@end
