import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Device sends this event once it decides the app is allowed to start a call, either from the built-in phone screens (iOS/_Recents_), or by the app calling `RNCallKeep.startCall`.
///
/// Try to start your app call action from here (e.g. get credentials of the user by `data.handle` and/or send INVITE to your SIP server)
/// Note: on iOS `callUUID` is not defined as the call is not yet managed by CallKit. You have to generate your own and call `startCall`.
/// [uuid] - The UUID of the call that is to be answered
/// [handle] - Phone number of the callee see [HandleType] for other options
typedef Future<dynamic> OnReceiveStartCallAction(String uuid, String handle);

/// User answer the incoming call
///
/// [uuid]- The UUID of the call that is to be answered.
typedef Future<dynamic> OnAnswerCallAction(String uuid);

/// User finish the call.
///
/// [uuid]- The UUID of the call that is to be ended.
typedef Future<dynamic> OnEndCallAction(String uuid);

/// The [AudioSession] has been activated by **FlutterCallKit**.
///
/// you might want to do following things when receiving this event:
/// - Start playing ringback if it is an outgoing call
typedef Future<dynamic> OnActivateAudioSession();

/// The [AudioSession] has been deactivated.
typedef Future<dynamic> OnDeactivateAudioSession();

/// Callback for [displayIncomingCall]
///
/// you might want to do following things when receiving this event:
/// Start playing ringback if it is an outgoing call
typedef Future<dynamic> OnIncomingCall(String error, String uuid, String handle,
    String localizedCallerName, bool fromPushKit);

/// A call was muted by the system or the user:
///
/// [muted] - whether the call was muted
/// [uuid] - The UUID of the call.
typedef Future<dynamic> OnMuted(bool muted, String uuid);

/// A call was held or unheld by the current user
///
/// [hold] - whether the call was held
/// [uuid] - The UUID of the call.
typedef Future<dynamic> OnHold(bool hold, String uuid);

/// Used to type a number on his dialer
///
/// [digits] - The digits that emitted the dtmf tone
/// [uuid] - The UUID of the call.
typedef Future<dynamic> OnDTMF(String digits, String uuid);

typedef Future<dynamic> OnStartCall(String handle, bool video);

enum HandleType { phoneNumber, generic, email }

enum EndReason {
  failed,
  remoteEnded,
  unanswered,
}

class IOSOptions {
  ///  It will be displayed on system UI when incoming calls received
  final String appName;

  /// If provided, it will be displayed on system UI during the call
  final String imageName;

  /// If provided, it will be played when incoming calls received; the system will use the default ringtone if this is not provided
  final String ringtoneSound;

  /// If provided, the maximum number of call groups supported by this application (Default: 3)
  final int maximumCallGroups;

  /// If provided, the maximum number of calls in a single group, used for conferencing (Default: 1, no conferencing)
  final int maximumCallsPerCallGroup;

  /// If provided, whether or not the application supports video calling (Default: true)
  final bool supportsVideo;

  /// If provided, whether or not the application saves calls in users recents call log (Default: true, iOS 11+ only)
  final bool includesCallsInRecents;

  IOSOptions(
    this.appName, {
    this.imageName = "",
    this.ringtoneSound = "",
    this.maximumCallGroups = 3,
    this.maximumCallsPerCallGroup = 1,
    this.supportsVideo = true,
    this.includesCallsInRecents = true,
  })  : assert(appName != null),
        assert(imageName != null),
        assert(ringtoneSound != null),
        assert(maximumCallGroups != null),
        assert(maximumCallsPerCallGroup != null),
        assert(supportsVideo != null),
        assert(includesCallsInRecents != null);

  Map<String, dynamic> toMap() {
    return {
      "appName": appName,
      "imageName": imageName,
      "ringtoneSound": ringtoneSound,
      "maximumCallGroups": maximumCallGroups?.toString(),
      "maximumCallsPerCallGroup": maximumCallsPerCallGroup?.toString(),
      "supportsVideo": supportsVideo,
      "includesCallsInRecents": includesCallsInRecents,
    };
  }
}

class FlutterCallKit {
  factory FlutterCallKit() => _instance;

  @visibleForTesting
  FlutterCallKit.private(MethodChannel channel) : _channel = channel;

  static final FlutterCallKit _instance = FlutterCallKit.private(
      const MethodChannel('com.peerwaya/flutter_callkit_plugin'));

  final MethodChannel _channel;

  OnReceiveStartCallAction _didReceiveStartCallAction;

  /// this means something big changed, so tell the Dart side. The Dart side should
  /// probably respond by hanging up all calls.
  VoidCallback _onProviderReset;

  OnAnswerCallAction _performAnswerCallAction;

  OnEndCallAction _performEndCallAction;

  OnActivateAudioSession _didActivateAudioSession;

  OnDeactivateAudioSession _didDeactivateAudioSession;

  OnIncomingCall _didDisplayIncomingCall;

  OnMuted _didPerformSetMutedCallAction;
  OnHold _didToggleHoldAction;
  OnDTMF _didPerformDTMFAction;

  OnStartCall _handleStartCallNotification;

  /// Configures with [options] and sets up handlers for incoming messages.
  void configure(
    IOSOptions options, {
    OnReceiveStartCallAction didReceiveStartCallAction,
    VoidCallback onProviderReset,
    OnAnswerCallAction performAnswerCallAction,
    OnEndCallAction performEndCallAction,
    OnActivateAudioSession didActivateAudioSession,
    OnDeactivateAudioSession didDeactivateAudioSession,
    OnIncomingCall didDisplayIncomingCall,
    OnMuted didPerformSetMutedCallAction,
    OnDTMF didPerformDTMFAction,
    OnHold didToggleHoldAction,
    OnStartCall handleStartCallNotification,
  }) {
    if (!Platform.isIOS) {
      return;
    }
    _didReceiveStartCallAction = didReceiveStartCallAction;
    _onProviderReset = onProviderReset;
    _performAnswerCallAction = performAnswerCallAction;
    _performEndCallAction = performEndCallAction;
    _didActivateAudioSession = didActivateAudioSession;
    _didDeactivateAudioSession = didDeactivateAudioSession;
    _didDisplayIncomingCall = didDisplayIncomingCall;
    _didPerformSetMutedCallAction = didPerformSetMutedCallAction;
    _didPerformDTMFAction = didPerformDTMFAction;
    _didToggleHoldAction = didToggleHoldAction;
    _handleStartCallNotification = handleStartCallNotification;
    _channel.setMethodCallHandler(_handleMethod);
    _channel.invokeMethod<void>('configure', options.toMap());
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case "didReceiveStartCallAction":
        if (_didReceiveStartCallAction == null) {
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _didReceiveStartCallAction(map["callUUID"], map["handle"]);
      case "onProviderReset":
        if (_onProviderReset == null) {
          return null;
        }
        return _onProviderReset();
      case "performAnswerCallAction":
        if (_performAnswerCallAction == null) {
          return null;
        }
        return _performAnswerCallAction(
            call.arguments.cast<String, dynamic>()["callUUID"]);
      case "performEndCallAction":
        if (_performEndCallAction == null) {
          return null;
        }
        return _performEndCallAction(
            call.arguments.cast<String, dynamic>()["callUUID"]);
      case "didActivateAudioSession":
        if (_didActivateAudioSession == null) {
          return null;
        }
        return _didActivateAudioSession();
      case "didDeactivateAudioSession":
        if (_didDeactivateAudioSession == null) {
          return null;
        }
        return _didDeactivateAudioSession();
      case "didDisplayIncomingCall":
        if (_didDisplayIncomingCall == null) {
          print("_didDisplayIncomingCall is null");
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _didDisplayIncomingCall(map["error"], map["callUUID"],
            map["handle"], map["localizedCallerName"], map["fromPushKit"]);
      case "didPerformSetMutedCallAction":
        if (_didPerformSetMutedCallAction == null) {
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _didPerformSetMutedCallAction(map["muted"], map["callUUID"]);
      case "didPerformDTMFAction":
        if (_didPerformDTMFAction == null) {
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _didPerformDTMFAction(map["digits"], map["callUUID"]);
      case "didToggleHoldAction":
        if (_didToggleHoldAction == null) {
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _didToggleHoldAction(map["hold"], map["callUUID"]);
      case "handleStartCallNotification":
        if (_handleStartCallNotification == null) {
          return null;
        }
        Map map = call.arguments.cast<String, dynamic>();
        return _handleStartCallNotification(map["handle"], map["video"]);
      default:
        throw UnsupportedError("Unrecognized JSON message");
    }
  }

  /// Display system UI for incoming calls
  ///
  /// An [uuid] that should be stored and re-used for [stopCall].
  /// A [handle] e.g Phone number of the caller
  /// A [handleType] which describes this [handle] see [HandleType]
  /// tell the system whether this is a [video] call
  Future<void> displayIncomingCall(
      String uuid, String handle, String localizedCallerName,
      {HandleType handleType = HandleType.phoneNumber,
      bool video = false}) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('displayIncomingCall', {
      "uuid": uuid,
      "handle": handle,
      "localizedCallerName": localizedCallerName,
      "handleType": handleTypeToString(handleType),
      "video": video,
    });
  }

  /// When you make an outgoing call, tell the device that a call is occurring.
  ///
  /// An [uuid] that should be stored and re-used for [stopCall].
  /// A [handle] e.g Phone number of the caller
  /// The [contactIdentifier] is displayed in the native call UI, and is typically the name of the call recipient.
  /// A [handleType] which describes this [handle] see [HandleType]
  /// tell the system whether this is a [video] call
  ///
  Future<void> startCall(String uuid, String handle, String contactIdentifier,
      {HandleType handleType = HandleType.phoneNumber,
      bool video = false}) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('startCall', {
      "uuid": uuid,
      "handle": handle,
      "contactIdentifier": contactIdentifier,
      "handleType": handleTypeToString(handleType),
      "video": video,
    });
  }

  Future<void> reportConnectingOutgoingCallWithUUID(String uuid) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>(
        'reportConnectingOutgoingCallWithUUID', uuid);
  }

  Future<void> reportConnectedOutgoingCallWithUUID(String uuid) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>(
        'reportConnectedOutgoingCallWithUUID', uuid);
  }

  /// Report that the call ended without the user initiating
  ///
  /// The [uuid] used for [startCall] or [displayIncomingCall]
  /// [reason] for the end call one of [EndReason]
  Future<void> reportEndCallWithUUID(String uuid, EndReason reason) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('reportEndCall', {
      'uuid': uuid,
      'reason': endReasonToInt(reason),
    });
  }

  Future<void> rejectCall(String uuid) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('endCall', uuid);
  }

  /// When you finish an incoming/outgoing call.
  ///
  /// The [uuid] used for `startCall` or `displayIncomingCall`

  Future<void> endCall(String uuid) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('endCall', uuid);
  }

  /// End all calls that have been started on the device.
  ///
  Future<void> endAllCalls() async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('endAllCalls');
  }

  /// Switch the mic on/off.
  ///
  /// [uuid] of the current call.
  /// set [mute] to true or false
  Future<void> setMutedCall(String uuid, bool mute) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('setMutedCall', {
      'uuid': uuid,
      'mute': mute,
    });
  }

  /// Checks if there are any active calls on the device and returns a future with a boolean value
  /// (`true` if there're active calls, `false` otherwise).
  ///
  Future<bool> checkIfBusy() async {
    if (!Platform.isIOS) {
      return null;
    }
    return await _channel.invokeMethod<void>('checkIfBusy') as bool;
  }

  /// Checks if the device speaker is on and returns a promise with a boolean value (`true` if speaker is on, `false` otherwise).
  ///
  Future<bool> checkSpeaker() async {
    if (!Platform.isIOS) {
      return null;
    }
    return await _channel.invokeMethod<void>('checkSpeaker') as bool;
  }

  /// Use this to update the display after an outgoing call has started.
  ///
  /// The [uuid] used for [startCall] or [displayIncomingCall]
  /// A [handle] e.g Phone number of the caller
  /// The [displayName] is the name of the caller to be displayed on the native UI
  /// A [handleType] which describes this [handle] see [HandleType]
  ///
  Future<void> updateDisplay(String uuid, String handle, String displayName,
      {HandleType handleType = HandleType.phoneNumber}) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('updateDisplay', {
      "uuid": uuid,
      "handle": handle,
      "handleType": handleTypeToString(handleType),
      "displayName": displayName,
    });
  }

  /// Set a call on/off hold.
  ///
  /// [uuid] of the current call.
  /// set [hold] to true or false

  Future<void> setOnHold(String uuid, bool hold) async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('setMutedCall', {
      'uuid': uuid,
      'hold': hold,
    });
  }

  Future<void> setReachable() async {
    if (!Platform.isIOS) {
      return;
    }
    await _channel.invokeMethod<void>('setReachable');
  }

  static String handleTypeToString(HandleType handleType) {
    switch (handleType) {
      case HandleType.generic:
        return "generic";
      case HandleType.phoneNumber:
        return "number";
      case HandleType.email:
        return "email";
      default:
        return "number";
    }
  }

  static int endReasonToInt(EndReason reason) {
    switch (reason) {
      case EndReason.failed:
        return 1;
      case EndReason.remoteEnded:
        return 2;
      case EndReason.unanswered:
        return 3;
      default:
        return 1;
    }
  }
}
