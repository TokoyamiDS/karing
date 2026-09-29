import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/utils/singbox_config_builder.dart';

/// The `proxy` selector is what `route.final` points at, so its active member
/// decides the exit node for everything. sing-box uses the selector's `default`
/// when present, otherwise its **first** member — and the first member is
/// AutoSelect, a URLTest group that re-picks the fastest node continuously.
///
/// Without an explicit `default`, a node chosen in the server list had no effect
/// at all: the connection went through AutoSelect and the exit country changed
/// by itself (observed live: `proxy` → AutoSelect → 🇦🇹 node).
void main() {
  List<dynamic> builtOutbounds({
    dynamic selectOutbound,
    Set<String>? allOutboundsTags,
  }) {
    return SingboxConfigBuilder.outbounds(
      "",
      allOutboundsTags ?? {'node-a', 'node-b'},
      {},
      selectOutbound,
      [
        {'type': 'vless', 'tag': 'node-a'},
        {'type': 'vless', 'tag': 'node-b'},
      ],
      null,
      {},
      SingboxExportType.karing,
    );
  }

  Map<String, dynamic> builtSelector({
    dynamic selectOutbound,
    Set<String>? allOutboundsTags,
  }) {
    return Map<String, dynamic>.from(
      builtOutbounds(
        selectOutbound: selectOutbound,
        allOutboundsTags: allOutboundsTags,
      ).cast<Map>().firstWhere((o) => o['tag'] == kOutboundTagProxy),
    );
  }

  test('a chosen node becomes the selector default', () {
    final sel = builtSelector(
      selectOutbound: {'type': 'vless', 'tag': 'node-b'},
    );

    expect(
      sel['default'],
      'node-b',
      reason: 'the picked node must actually be used, not just listed',
    );
    expect(sel['outbounds'], contains('node-b'));
  });

  test('the selector default is always one of its own members', () {
    for (final tag in ['node-a', 'node-b', 'AutoSelect', 'not-a-member']) {
      final sel = builtSelector(
        selectOutbound: {'type': 'vless', 'tag': tag},
      );
      expect(
        sel['outbounds'],
        contains(sel['default']),
        reason: 'default $tag resolved to ${sel['default']}, which is not a member',
      );
    }
  });

  test('selecting the URLTest group maps to AutoSelect, not to "urltest"', () {
    // getUrltest() tags the group `urltest`, but the builder re-tags the
    // emitted outbound to AutoSelect. Copying the tag verbatim would leave the
    // selector pointing at a tag that does not exist.
    final sel = builtSelector(
      selectOutbound: {'type': 'urltest', 'tag': kOutboundTagUrltest},
    );

    expect(sel['default'], kOutboundTagAutoSelect);
    expect(sel['outbounds'], isNot(contains(kOutboundTagUrltest)));
  });

  test('no selection keeps the previous AutoSelect behaviour', () {
    expect(builtSelector()['default'], kOutboundTagAutoSelect);
    expect(
      builtSelector(selectOutbound: {'type': 'vless', 'tag': 'not-a-member'})['default'],
      kOutboundTagAutoSelect,
      reason: 'a tag that is not a member must not become a dangling default',
    );
  });

  test('the selector still lists AutoSelect first, so the UI order is stable', () {
    final sel = builtSelector(
      selectOutbound: {'type': 'vless', 'tag': 'node-a'},
    );
    expect((sel['outbounds'] as List).first, kOutboundTagAutoSelect);
  });

  test('a node switch must not tear down connections that are already running', () {
    // AI assistants answer over long-lived streaming connections. Interrupting
    // on every switch is what made them drop mid-answer and report a retry, so
    // both groups have to leave existing connections alone.
    final byTag = {
      for (final ob in builtOutbounds().cast<Map>())
        ob['tag']?.toString(): ob,
    };

    for (final tag in [kOutboundTagProxy, kOutboundTagAutoSelect]) {
      expect(
        byTag[tag]?['interrupt_exist_connections'],
        isFalse,
        reason: '$tag must not interrupt existing connections on a switch',
      );
    }
  });
}
