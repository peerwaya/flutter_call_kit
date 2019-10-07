#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <Intents/Intents.h>

@interface FlutterCallKitPlugin : NSObject<FlutterPlugin, CXProviderDelegate>
@property (nonatomic, strong) CXCallController *callKitCallController;
@property (nonatomic, strong) CXProvider *callKitProvider;

+ (void)reportNewIncomingCall:(NSString *)uuidString
                       handle:(NSString *)handle
                   handleType:(NSString *)handleType
                     hasVideo:(BOOL)hasVideo
          localizedCallerName:(NSString * _Nullable)localizedCallerName
                  fromPushKit:(BOOL)fromPushKit;
@end
