# Flutter Call Kit

[![pub package](https://img.shields.io/pub/v/flutter_call_kit.svg)](https://pub.dartlang.org/packages/flutter_call_kit)
Flutter Call Kit Plugin - Currently iOS >= 10.0 only

## Motivation

**Flutter Call Kit** utilises a brand new iOS 10 framework **CallKit**  to make the life easier for VoIP developers using Flutter.

**Note 1**: This plugin works for only iOS. No android support yet

**Note 2** This plugin was inspired by [react-native-keep](https://github.com/react-native-webrtc/react-native-callkeep)

For more information about **CallKit** on iOS, please see [Official CallKit Framework Document](https://developer.apple.com/reference/callkit?language=objc) or [Introduction to CallKit by Xamarin](https://developer.xamarin.com/guides/ios/platform_features/introduction-to-ios10/callkit/)


## iOS
![Connection Service](https://github.com/react-native-webrtc/react-native-callkeep/blob/master/docs/pictures/call-kit.png)

## Usage
Add `flutter_call_kit` as a [dependency in your pubspec.yaml file](https://flutter.io/using-packages/).


## Example

```dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter_call_kit/flutter_call_kit.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _configured;
  String _currentCallId;
  FlutterCallKit _callKit = FlutterCallKit();
  @override
  void initState() {
    super.initState();
    configure();
  }

  Future<void> configure() async {
    _callKit.configure(
      IOSOptions("My Awesome APP",
          imageName: 'sim_icon',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1),
      didReceiveStartCallAction: _didReceiveStartCallAction,
      performAnswerCallAction: _performAnswerCallAction,
      performEndCallAction: _performEndCallAction,
      didActivateAudioSession: _didActivateAudioSession,
      didDisplayIncomingCall: _didDisplayIncomingCall,
      didPerformSetMutedCallAction: _didPerformSetMutedCallAction,
      didPerformDTMFAction: _didPerformDTMFAction,
      didToggleHoldAction: _didToggleHoldAction,
    );
    setState(() {
      _configured = true;
    });
  }

  /// Use startCall to ask the system to start a call - Initiate an outgoing call from this point
  Future<void> startCall(String handle, String localizedCallerName) async {
    /// Your normal start call action
    await _callKit.startCall(currentCallId, handle, localizedCallerName);
  }

  Future<void> reportEndCallWithUUID(String uuid, EndReason reason) async {
    await _callKit.reportEndCallWithUUID(uuid, reason);
  }

  /// Event Listener Callbacks

  Future<void> _didReceiveStartCallAction(String uuid, String handle) async {
    // Get this event after the system decides you can start a call
    // You can now start a call from within your app
  }

  Future<void> _performAnswerCallAction(String uuid) async {
    // Called when the user answers an incoming call
  }

  Future<void> _performEndCallAction(String uuid) async {
    await _callKit.endCall(this.currentCallId);
    _currentCallId = null;
  }

  Future<void> _didActivateAudioSession() async {
    // you might want to do following things when receiving this event:
    // - Start playing ringback if it is an outgoing call
  }

  Future<void> _didDisplayIncomingCall(String error, String uuid, String handle,
      String localizedCallerName, bool fromPushKit) async {
    // You will get this event after RNCallKeep finishes showing incoming call UI
    // You can check if there was an error while displaying
  }

  Future<void> _didPerformSetMutedCallAction(bool mute, String uuid) async {
    // Called when the system or user mutes a call
  }

  Future<void> _didPerformDTMFAction(String digit, String uuid) async {
    // Called when the system or user performs a DTMF action
  }

  Future<void> _didToggleHoldAction(bool hold, String uuid) async {
    // Called when the system or user holds a call
  }

  String get currentCallId {
    if (_currentCallId == null) {
      final uuid = new Uuid();
      _currentCallId = uuid.v4();
    }

    return _currentCallId;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Text('Flutter Call Kit Configured: $_configured\n'),
        ),
      ),
    );
  }
}

```

## Receiving a call when the application is not reachable.

In some case your application can be unreachable :
- when the user kill the application
- when it's in background since a long time (eg: after ~5mn the os will kill all connections).

To be able to wake up your application to display the incoming call, you can use [https://github.com/peerwaya/flutter_voip_push_notification](flutter_voip_push_notification) on iOS.

You have to send a push to your application with a library supporting PushKit pushes for iOS.

### PushKit

Since iOS 13, you'll have to report the incoming calls that wakes up your application with a VoIP push. Add this in your `AppDelegate.m` if you're using VoIP pushes to wake up your application :

```objective-c
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type withCompletionHandler:(void (^)(void))completion {
  // Process the received push
  [FlutterVoipPushNotificationPlugin didReceiveIncomingPushWithPayload:payload forType:(NSString *)type];

  // Retrieve information like handle and callerName here
  // NSString *uuid = /* fetch for payload or ... */ [[[NSUUID UUID] UUIDString] lowercaseString];
  // NSString *callerName = @"caller name here";
  // NSString *handle = @"caller number here";

  [FlutterCallKitPlugin reportNewIncomingCall:uuid handle:handle handleType:@"generic" hasVideo:false localizedCallerName:callerName fromPushKit: YES];

  completion();
}
```

## Contributing

Any pull request, issue report and suggestion are highly welcome!