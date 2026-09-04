/// Generates ECH client subnet payload from geosite (no-op minimal version).
class GeoipSubnetUtils {
  static String genClientSubnet(List<String> subnets) {
    return subnets.join(',');
  }

  static Future<void> saveSubnets(String path, List<String> subnets) async {}
}
