import 'dart:convert';

import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('vn.czn.viethoa/patcher');
  static const progress = EventChannel('vn.czn.viethoa/progress');
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
}
