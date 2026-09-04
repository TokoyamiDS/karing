/// Parse and fix URIs with bare IPv6 hosts.
class UriUtils {
  static Uri? parseUrlFixIPV6(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return null;
      }
      if (uri.host.contains(':') && !url.contains('[')) {
        // re-wrap bare ipv6
        final schemeEnd = url.indexOf('://');
        if (schemeEnd > 0) {
          final rest = url.substring(schemeEnd + 3);
          final slash = rest.indexOf('/');
          final hostPart = slash > 0 ? rest.substring(0, slash) : rest;
          final at = hostPart.lastIndexOf('@');
          final hostNoUser = at >= 0 ? hostPart.substring(at + 1) : hostPart;
          final colon = hostNoUser.lastIndexOf(':');
          if (colon >= 0 && hostNoUser.contains(':')) {
            final host = hostNoUser.substring(0, colon);
            final port = hostNoUser.substring(colon + 1);
            final fixed =
                '${url.substring(0, schemeEnd + 3)}${at >= 0 ? '${hostPart.substring(0, at + 1)}' : ''}[$host]:$port${slash > 0 ? rest.substring(slash) : ''}';
            return Uri.tryParse(fixed);
          }
        }
      }
      return uri;
    } catch (_) {
      return null;
    }
  }
}
