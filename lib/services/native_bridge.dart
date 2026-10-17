import 'dart:convert';

import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('vn.czn.viethoa/patcher');
  static const progress = EventChannel('vn.czn.viethoa/progress');
  static Stream<dynamic> get progressEvents =>
      progress.receiveBroadcastStream();
  static Future<Map<String, dynamic>> map(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final result = await channel.invokeMapMethod<String, dynamic>(method, args);
    return result ?? <String, dynamic>{};
  }

  static Future<bool> action(
    String method, [
    Map<String, dynamic>? args,
  ]) async => await channel.invokeMethod<bool>(method, args) ?? false;
  static Future<String> download(
    Map<String, dynamic> info, {
    bool apk = false,
  }) async =>
      await channel.invokeMethod<String>(
        apk ? 'downloadApp' : 'downloadPatch',
        {'channelJson': jsonEncode(info)},
      ) ??
      '';

  static Future<bool> canDrawOverlays() async =>
      await channel.invokeMethod<bool>('canDrawOverlays') ?? false;

  static Future<bool> requestOverlayPermission() async =>
      await channel.invokeMethod<bool>('requestOverlayPermission') ?? false;

  static Future<bool> startChibiOverlay() async =>
      await channel.invokeMethod<bool>('startChibiOverlay') ?? false;

  static Future<bool> stopChibiOverlay() async =>
      await channel.invokeMethod<bool>('stopChibiOverlay') ?? false;

  static Future<bool> isChibiOverlayRunning() async =>
      await channel.invokeMethod<bool>('isChibiOverlayRunning') ?? false;

  static Future<bool> checkCompanionLaunchIntent() async =>
      await channel.invokeMethod<bool>('checkCompanionLaunchIntent') ?? false;

  static Future<String?> getWifiIp() async =>
      await channel.invokeMethod<String>('getWifiIp');

  static Future<bool> isLocalAdbConnected() async =>
      await channel.invokeMethod<bool>('isLocalAdbConnected') ?? false;

  static Future<bool> pairLocalAdb(
    int port,
    String code, {
    String? host,
  }) async =>
      await channel.invokeMethod<bool>('pairLocalAdb', {
        'host': host,
        'port': port,
        'code': code,
      }) ??
      false;

  static Future<bool> connectLocalAdb(
    int port, {
    String? host,
  }) async =>
      await channel.invokeMethod<bool>('connectLocalAdb', {
        'host': host,
        'port': port,
      }) ??
      false;

  static Future<bool> openDevSettings() async =>
      await channel.invokeMethod<bool>('openDevSettings') ?? false;
}
