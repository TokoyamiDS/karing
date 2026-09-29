import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/modules/setting_manager.dart';

/// The "Recommended" strip shows the best N nodes, ranked either by the delay
/// test (`latency`) or by how long the exit-IP lookup took (`cost`). Both are
/// persisted, and the count is clamped on load — an out-of-range stored value
/// must fall back rather than blank the strip or read a negative number of
/// nodes.
void main() {
  SettingConfigItemUIScreen load(Map<String, dynamic> map) =>
      SettingConfigItemUIScreen.fromJsonStatic(map);

  test('the count defaults to three, as it always did', () {
    expect(
      load({}).recommendServerCount,
      SettingConfigItemUIScreen.kRecommendServerCountDefault,
    );
  });

  test('a chosen count round-trips', () {
    expect(load({'recommend_server_count': 7}).recommendServerCount, 7);
    expect(load({'recommend_server_count': 1}).recommendServerCount, 1);
  });

  test('an out-of-range count falls back instead of sticking', () {
    for (final bad in [0, -4, 9999]) {
      expect(
        load({'recommend_server_count': bad}).recommendServerCount,
        SettingConfigItemUIScreen.kRecommendServerCountDefault,
        reason: 'a stored $bad would show nothing or far too much',
      );
    }
  });

  test('the sort key defaults to latency', () {
    expect(
      load({}).recommendSortBy,
      SettingConfigItemUIScreen.kRecommendSortByLatency,
    );
  });

  test('the sort key round-trips to IP lookup time', () {
    expect(
      load({
        'recommend_sort_by': SettingConfigItemUIScreen.kRecommendSortByCost,
      }).recommendSortBy,
      SettingConfigItemUIScreen.kRecommendSortByCost,
    );
  });

  test('the two sort keys are distinct values', () {
    expect(
      SettingConfigItemUIScreen.kRecommendSortByLatency,
      isNot(SettingConfigItemUIScreen.kRecommendSortByCost),
      reason: 'the picker compares the stored key, so they cannot collide',
    );
  });
}
