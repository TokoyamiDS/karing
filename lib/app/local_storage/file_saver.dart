// ignore_for_file: unused_catch_stack, empty_catches

import 'dart:convert';
import 'dart:io';

import 'package:karing/app/utils/log.dart';

/// Saves json to a preconfigured path, one file per instance.
class FileSaver {
  bool _saving = false;
  dynamic _dirtyObject;
  String _savePath = "";

  void setSavePath(String path) {
    _savePath = path;
  }

  String getSavePath() {
    return _savePath;
  }

  Future<bool> saveAsJson(dynamic obj) async {
    if (_savePath.isEmpty) {
      return false;
    }
    if (_saving) {
      _dirtyObject = obj;
      return true;
    }
    bool hasErr = false;
    _saving = true;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(obj);
      final file = File(_savePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } catch (err) {
      hasErr = true;
      Log.w("FileSaver.saveAsJson exception ${err.toString()}");
    }
    _saving = false;
    if (_dirtyObject != null) {
      final dirtyObject = _dirtyObject;
      _dirtyObject = null;
      Future.delayed(const Duration(milliseconds: 50), () {
        saveAsJson(dirtyObject);
      });
    }
    return !hasErr;
  }

  Future<bool> saveAsString(String content) async {
    if (_savePath.isEmpty) {
      return false;
    }
    try {
      final file = File(_savePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      return true;
    } catch (err) {
      Log.w("FileSaver.saveAsString exception ${err.toString()}");
      return false;
    }
  }
}
