import 'package:karing/app/utils/proxy_conf_utils.dart';

/// Generates unique tags for outbounds.
class TagGen {
  final Map<String, int> _tags;
  TagGen({required Map<String, int> tags}) : _tags = tags;

  String gen(String tag) {
    String out = tag;
    int count = 1;
    while (_tags.containsKey(out)) {
      out = "$tag ${count++}";
    }
    _tags[out] = 1;
    return out;
  }
}

/// Simple parallel task queue with concurrency limit.
class ParallelTaskQueue {
  final int _concurrency;
  final List<Future<void> Function()> _tasks = [];
  int _running = 0;

  ParallelTaskQueue({int concurrency = 4}) : _concurrency = concurrency < 1 ? 1 : concurrency;

  void add(Future<void> Function() task) {
    _tasks.add(task);
    _schedule();
  }

  void _schedule() {
    while (_running < _concurrency && _tasks.isNotEmpty) {
      _running++;
      final task = _tasks.removeAt(0);
      task().whenComplete(() {
        _running--;
        _schedule();
      });
    }
  }

  Future<void> wait() async {
    while (_running > 0 || _tasks.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Converts dns server urls to outbound tags.
class DnsUtils {
  static String tagFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host;
    if (host.isEmpty) return url;
    return host;
  }

  static String normalizeServer(String server) {
    if (server.contains("://")) {
      return server;
    }
    if (server.startsWith("local")) {
      return server;
    }
    return server;
  }
}

/// strategies for proxy select as string helpers.
String proxyStrategyToString(ProxyStrategy s) {
  switch (s) {
    case ProxyStrategy.preferProxy:
      return "preferProxy";
    case ProxyStrategy.preferDirect:
      return "preferDirect";
    case ProxyStrategy.onlyProxy:
      return "onlyProxy";
    case ProxyStrategy.onlyDirect:
      return "onlyDirect";
  }
}

ProxyStrategy proxyStrategyFromString(String s) {
  switch (s) {
    case "preferProxy":
      return ProxyStrategy.preferProxy;
    case "onlyProxy":
      return ProxyStrategy.onlyProxy;
    case "onlyDirect":
      return ProxyStrategy.onlyDirect;
    default:
      return ProxyStrategy.preferDirect;
  }
}
