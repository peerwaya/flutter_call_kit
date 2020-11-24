#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <Intents/Intents.h>

API_AVAILABLE(ios(10.0))
@interface FlutterCallKitPlugin : NSObject<FlutterPlugin, CXProviderDelegate>
@property (nonatomic, strong) CXCallController * _Nullable callKitCallController;
@property (nonatomic, strong) CXProvider * _Nullable callKitProvider;

+ (void)reportNewIncomingCall:(NSString *_Nonnull)uuidString
                       handle:(NSString *_Nonnull)handle
                   handleType:(NSString *_Nonnull)handleType
                     hasVideo:(BOOL)hasVideo
          localizedCallerName:(NSString * _Nullable)localizedCallerName
                  fromPushKit:(BOOL)fromPushKit;
@end
