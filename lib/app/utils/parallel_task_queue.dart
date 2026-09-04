import 'dart:async';

/// Task queue with concurrency, per-task progress callback and cancellation.
/// Signature matches karing usage:
/// ParallelTaskQueue(task, onProgress, concurrency, initialArgs)
class ParallelTaskQueue {
  final Future<dynamic> Function(dynamic arg) _task;
  final void Function(dynamic arg, int left, int total, bool start, bool finish)?
      _onProgress;
  final int _concurrency;
  final List<dynamic> _args;
  final List<dynamic> _pending = [];
  final Set<dynamic> _enqueued = {};
  int _running = 0;
  bool _started = false;
  bool _cancelled = false;
  int _total = 0;

  ParallelTaskQueue(this._task, this._onProgress, this._concurrency, this._args);

  final List<Completer<dynamic>> _completers = [];

  bool hasTask(dynamic arg) {
    return _enqueued.contains(arg);
  }

  bool running(dynamic arg) {
    return _runningTasks.contains(arg);
  }

  final Set<dynamic> _runningTasks = {};

  void addTasks(List<dynamic> args) {
    for (final arg in args) {
      if (!_enqueued.contains(arg)) {
        _enqueued.add(arg);
        _pending.add(arg);
      }
    }
    _total = _pending.length;
  }

  void run() {
    _started = true;
    _schedule();
  }

  void _schedule() {
    if (_cancelled) {
      return;
    }
    while (_running < _concurrency && _pending.isNotEmpty) {
      final arg = _pending.removeAt(0);
      _running++;
      _runningTasks.add(arg);
      _onProgress?.call(arg, _pending.length, _total, true, false);
      _task(arg).then((value) {
        _running--;
        _runningTasks.remove(arg);
        _onProgress?.call(arg, _pending.length, _total, false,
            _pending.isEmpty && _running == 0);
        _schedule();
      }).catchError((err) {
        _running--;
        _runningTasks.remove(arg);
        _onProgress?.call(arg, _pending.length, _total, false,
            _pending.isEmpty && _running == 0);
        _schedule();
      });
    }
  }

  void cancel() {
    _cancelled = true;
    _pending.clear();
    _enqueued.clear();
  }
}
