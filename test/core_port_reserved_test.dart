import 'package:flutter_test/flutter_test.dart';
import 'package:karing/app/local_services/vpn_service.dart';

/// Windows refuses to bind a port inside a WinNAT / Hyper-V reserved range
/// with wording that reads like a permissions problem. The app rewrites that
/// one case into an actionable message, so the matcher has to be precise:
/// a false positive would replace a genuine startup error with the wrong
/// explanation.
void main() {
  test('matches the reserved-port bind failure', () {
    // Verbatim sing-box stderr, captured on this machine.
    const real =
        'FATAL[0000] start service: start inbound/mixed[mixed-in]: listen tcp '
        '127.0.0.1:3067: bind: An attempt was made to access a socket in a way '
        'forbidden by its access permissions.';
    expect(VPNService.isReservedPortFailure(real), isTrue);
  });

  test('matches the port-already-in-use variant', () {
    expect(
      VPNService.isReservedPortFailure(
        'bind: Only one usage of each socket address is normally permitted.',
      ),
      isTrue,
    );
  });

  test('does not match unrelated startup errors', () {
    // A config error also mentions neither bind nor the socket wording.
    expect(
      VPNService.isReservedPortFailure(
        'FATAL decode config at ...: unknown field "foo"',
      ),
      isFalse,
    );
    // A bind failure for a different reason must not be rewritten either.
    expect(
      VPNService.isReservedPortFailure('bind: address already in use'),
      isFalse,
    );
    expect(VPNService.isReservedPortFailure(''), isFalse);
  });

  test('requires the bind: prefix, not just the wording', () {
    // "forbidden" alone can appear in unrelated text.
    expect(
      VPNService.isReservedPortFailure(
        'access to the forbidden resource was denied',
      ),
      isFalse,
    );
  });
}
