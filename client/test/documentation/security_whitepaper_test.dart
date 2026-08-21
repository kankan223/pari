import 'package:civic_commons/documentation/domain/security_whitepaper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.4 — Security Whitepaper Domain', () {
    group('SecurityControlCategory', () {
      test('has 7 categories', () {
        expect(SecurityControlCategory.values.length, 7);
      });

      test('label returns human-readable name', () {
        expect(SecurityControlCategory.encryption.label, 'Encryption');
        expect(SecurityControlCategory.authentication.label, 'Authentication');
        expect(SecurityControlCategory.authorization.label, 'Authorization');
        expect(SecurityControlCategory.networkSecurity.label, 'Network Security');
        expect(SecurityControlCategory.logging.label, 'Logging');
        expect(SecurityControlCategory.dataRetention.label, 'Data Retention');
        expect(SecurityControlCategory.deviceSecurity.label, 'Device Security');
      });
    });

    group('OwaspDomain', () {
      test('has 6 domains', () {
        expect(OwaspDomain.values.length, 6);
      });

      test('label returns OWASP identifier', () {
        expect(OwaspDomain.networkSecurity.label, 'MASVS-NETWORK');
        expect(OwaspDomain.dataStorage.label, 'MASVS-STORAGE');
        expect(OwaspDomain.cryptography.label, 'MASVS-CRYPTO');
        expect(OwaspDomain.authentication.label, 'MASVS-AUTH');
        expect(OwaspDomain.platformInteraction.label, 'MASVS-PLATFORM');
        expect(OwaspDomain.codeQuality.label, 'MASVS-RESILIENCE');
      });
    });

    group('SecurityControl', () {
      test('constructs with required fields', () {
        const control = SecurityControl(
          id: 'SC-001',
          name: 'Argon2id Blind Hashing',
          category: SecurityControlCategory.encryption,
          description: 'Phone numbers are hashed with Argon2id.',
          implementation: 'RFC 9106 compliant Argon2id with sealed Vault salt.',
        );
        expect(control.id, 'SC-001');
        expect(control.category, SecurityControlCategory.encryption);
        expect(control.isActive, true);
        expect(control.threatCount, 0);
      });

      test('threatCount returns mitigated threats count', () {
        const control = SecurityControl(
          id: 'SC-001',
          name: 'Encryption',
          category: SecurityControlCategory.encryption,
          description: 'AES-256-GCM',
          implementation: 'Local cipher',
          mitigatedThreats: ['Data Exposure', 'MITM'],
        );
        expect(control.threatCount, 2);
      });

      test('equality by id', () {
        const a = SecurityControl(
          id: 'SC-1', name: 'A', category: SecurityControlCategory.encryption,
          description: 'd', implementation: 'i');
        const b = SecurityControl(
          id: 'SC-1', name: 'B', category: SecurityControlCategory.logging,
          description: 'e', implementation: 'j');
        const c = SecurityControl(
          id: 'SC-2', name: 'A', category: SecurityControlCategory.encryption,
          description: 'd', implementation: 'i');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('ThreatModelEntry', () {
      test('constructs with required fields', () {
        const threat = ThreatModelEntry(
          id: 'THR-001',
          name: 'Data Exposure',
          description: 'Sensitive data exposed to unauthorized parties.',
          strideCategory: 'Information Disclosure',
          impactLevel: 'high',
        );
        expect(threat.id, 'THR-001');
        expect(threat.isMitigated, false);
      });

      test('isMitigated is true when controls exist', () {
        const mitigated = ThreatModelEntry(
          id: 'THR-1', name: 'T', description: 'D',
          strideCategory: 'S', impactLevel: 'h',
          mitigatingControlIds: ['SC-1'],
        );
        const open = ThreatModelEntry(
          id: 'THR-2', name: 'T', description: 'D',
          strideCategory: 'S', impactLevel: 'h',
        );
        expect(mitigated.isMitigated, true);
        expect(open.isMitigated, false);
      });

      test('equality by id', () {
        const a = ThreatModelEntry(id: 'T1', name: 'A', description: 'd', strideCategory: 's', impactLevel: 'h');
        const b = ThreatModelEntry(id: 'T1', name: 'B', description: 'e', strideCategory: 's', impactLevel: 'l');
        const c = ThreatModelEntry(id: 'T2', name: 'A', description: 'd', strideCategory: 's', impactLevel: 'h');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('SecurityWhitepaper', () {
      test('constructs with controls and threats', () {
        const wp = SecurityWhitepaper(
          appName: 'Civic Commons',
          version: '1.0',
          lastReviewed: '2026-08-21',
          controls: [
            SecurityControl(id: 'SC-1', name: 'Encryption', category: SecurityControlCategory.encryption, description: 'AES', implementation: 'GCM'),
          ],
          threats: [
            ThreatModelEntry(id: 'THR-1', name: 'Exposure', description: 'Data leak', strideCategory: 'Info', impactLevel: 'high', mitigatingControlIds: ['SC-1']),
          ],
          encryptionAlgorithms: ['AES-256-GCM', 'Argon2id', 'X25519'],
        );
        expect(wp.controlCount, 1);
        expect(wp.threatCount, 1);
        expect(wp.mitigatedThreats.length, 1);
        expect(wp.encryptionAlgorithms.length, 3);
      });

      test('activeControls returns only active', () {
        const wp = SecurityWhitepaper(
          appName: 'App', version: '1.0', lastReviewed: '2026-01-01',
          controls: [
            SecurityControl(id: 'SC-1', name: 'A', category: SecurityControlCategory.encryption, description: 'd', implementation: 'i', isActive: true),
            SecurityControl(id: 'SC-2', name: 'B', category: SecurityControlCategory.logging, description: 'd', implementation: 'i', isActive: false),
          ],
        );
        expect(wp.activeControls.length, 1);
      });

      test('unmitigatedThreats returns open threats', () {
        const wp = SecurityWhitepaper(
          appName: 'App', version: '1.0', lastReviewed: '2026-01-01',
          threats: [
            ThreatModelEntry(id: 'T1', name: 'Open', description: 'd', strideCategory: 's', impactLevel: 'h'),
            ThreatModelEntry(id: 'T2', name: 'Mitigated', description: 'd', strideCategory: 's', impactLevel: 'h', mitigatingControlIds: ['SC-1']),
          ],
        );
        expect(wp.unmitigatedThreats.length, 1);
        expect(wp.mitigatedThreats.length, 1);
      });

      test('controlsByCategory filters correctly', () {
        const wp = SecurityWhitepaper(
          appName: 'App', version: '1.0', lastReviewed: '2026-01-01',
          controls: [
            SecurityControl(id: 'SC-1', name: 'Enc', category: SecurityControlCategory.encryption, description: 'd', implementation: 'i'),
            SecurityControl(id: 'SC-2', name: 'Log', category: SecurityControlCategory.logging, description: 'd', implementation: 'i'),
          ],
        );
        expect(wp.controlsByCategory(SecurityControlCategory.encryption).length, 1);
        expect(wp.controlsByCategory(SecurityControlCategory.logging).length, 1);
      });

      test('controlsForOwasp filters correctly', () {
        const wp = SecurityWhitepaper(
          appName: 'App', version: '1.0', lastReviewed: '2026-01-01',
          controls: [
            SecurityControl(id: 'SC-1', name: 'Crypto', category: SecurityControlCategory.encryption, description: 'd', implementation: 'i', owaspDomains: [OwaspDomain.cryptography]),
            SecurityControl(id: 'SC-2', name: 'Net', category: SecurityControlCategory.networkSecurity, description: 'd', implementation: 'i', owaspDomains: [OwaspDomain.networkSecurity]),
          ],
        );
        expect(wp.controlsForOwasp(OwaspDomain.cryptography).length, 1);
        expect(wp.controlsForOwasp(OwaspDomain.networkSecurity).length, 1);
      });

      test('equality by appName and version', () {
        const a = SecurityWhitepaper(appName: 'App', version: '1.0', lastReviewed: '2026-01-01');
        const b = SecurityWhitepaper(appName: 'App', version: '1.0', lastReviewed: '2026-12-31');
        const c = SecurityWhitepaper(appName: 'App', version: '2.0', lastReviewed: '2026-01-01');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in control category labels', () {
        for (final cat in SecurityControlCategory.values) {
          expect(cat.label, isNot(contains('@')));
          expect(cat.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in OWASP domain labels', () {
        for (final domain in OwaspDomain.values) {
          expect(domain.label, isNot(contains('@')));
        }
      });
    });
  });
}
