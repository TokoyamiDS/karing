class VersionCompareUtils {
  static int compareVersion(String ver1, String ver2) {
    return compareVersionWithLength(ver1, ver2);
  }
}

int compareVersionWithLength(String a, String b, [int? maxSegments]) {
  final pa = a.split('.');
  final pb = b.split('.');
  int len = pa.length > pb.length ? pa.length : pb.length;
  if (maxSegments != null && len > maxSegments) {
    len = maxSegments;
  }
  for (int i = 0; i < len; i++) {
    final na = int.tryParse(i < pa.length ? pa[i] : '0') ?? 0;
    final nb = int.tryParse(i < pb.length ? pb[i] : '0') ?? 0;
    if (na != nb) {
      return na.compareTo(nb);
    }
  }
  return 0;
}
