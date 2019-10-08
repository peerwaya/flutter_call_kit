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
