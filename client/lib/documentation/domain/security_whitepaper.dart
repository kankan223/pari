/// Security whitepaper domain models for handover documentation (Task 15.4).
///
/// Defines structured security architecture documentation: threat models,
/// security controls, encryption details, and compliance mappings.
/// All values are pure — no identity, no PII, no secrets, no credentials.

/// Category of security control.
enum SecurityControlCategory {
  /// Data encryption and at-rest protection.
  encryption,

  /// Authentication and identity verification.
  authentication,

  /// Authorization and access control.
  authorization,

  /// Network security and transport.
  networkSecurity,

  /// Logging and audit controls.
  logging,

  /// Data retention and deletion.
  dataRetention,

  /// Device and platform security.
  deviceSecurity;

  /// Human-readable label.
  String get label {
    switch (this) {
      case SecurityControlCategory.encryption:
        return 'Encryption';
      case SecurityControlCategory.authentication:
        return 'Authentication';
      case SecurityControlCategory.authorization:
        return 'Authorization';
      case SecurityControlCategory.networkSecurity:
        return 'Network Security';
      case SecurityControlCategory.logging:
        return 'Logging';
      case SecurityControlCategory.dataRetention:
        return 'Data Retention';
      case SecurityControlCategory.deviceSecurity:
        return 'Device Security';
    }
  }
}

/// OWASP MASVS domain mapping.
enum OwaspDomain {
  /// Network security.
  networkSecurity,

  /// Data storage.
  dataStorage,

  /// Cryptography.
  cryptography,

  /// Authentication and session management.
  authentication,

  /// Platform interaction.
  platformInteraction,

  /// Code quality and resilience.
  codeQuality;

  /// Human-readable label.
  String get label {
    switch (this) {
      case OwaspDomain.networkSecurity:
        return 'MASVS-NETWORK';
      case OwaspDomain.dataStorage:
        return 'MASVS-STORAGE';
      case OwaspDomain.cryptography:
        return 'MASVS-CRYPTO';
      case OwaspDomain.authentication:
        return 'MASVS-AUTH';
      case OwaspDomain.platformInteraction:
        return 'MASVS-PLATFORM';
      case OwaspDomain.codeQuality:
        return 'MASVS-RESILIENCE';
    }
  }
}

/// A single security control documented in the whitepaper.
class SecurityControl {
  /// Unique identifier (e.g., 'SC-001').
  final String id;

  /// Control name (e.g., 'Argon2id Blind Hashing').
  final String name;

  /// Category of this control.
  final SecurityControlCategory category;

  /// Detailed description of the control.
  final String description;

  /// Implementation details.
  final String implementation;

  /// Which threat(s) this control mitigates.
  final List<String> mitigatedThreats;

  /// Related OWASP domains.
  final List<OwaspDomain> owaspDomains;

  /// Whether this control is currently active.
  final bool isActive;

  const SecurityControl({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.implementation,
    this.mitigatedThreats = const [],
    this.owaspDomains = const [],
    this.isActive = true,
  });

  /// Number of threats mitigated.
  int get threatCount => mitigatedThreats.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityControl &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A threat in the threat model.
class ThreatModelEntry {
  /// Unique identifier (e.g., 'THR-001').
  final String id;

  /// Threat name.
  final String name;

  /// Description of the threat.
  final String description;

  /// STRIDE category (Spoofing, Tampering, Repudiation, Info Disclosure, DoS, Elevation).
  final String strideCategory;

  /// Impact level (low, medium, high, critical).
  final String impactLevel;

  /// Mitigating control IDs.
  final List<String> mitigatingControlIds;

  const ThreatModelEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.strideCategory,
    required this.impactLevel,
    this.mitigatingControlIds = const [],
  });

  /// Whether this threat has been mitigated by at least one control.
  bool get isMitigated => mitigatingControlIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreatModelEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A complete security whitepaper.
class SecurityWhitepaper {
  /// Application name.
  final String appName;

  /// Document version.
  final String version;

  /// Date of last review (ISO 8601).
  final String lastReviewed;

  /// Document author (role-based, not personal).
  final String authorRole;

  /// Security controls documented.
  final List<SecurityControl> controls;

  /// Threat model entries.
  final List<ThreatModelEntry> threats;

  /// Encryption algorithms used.
  final List<String> encryptionAlgorithms;

  /// Compliance frameworks addressed.
  final List<String> complianceFrameworks;

  /// Security audit date (ISO 8601).
  final String? lastAuditDate;

  /// Next scheduled audit date (ISO 8601).
  final String? nextAuditDate;

  const SecurityWhitepaper({
    required this.appName,
    required this.version,
    required this.lastReviewed,
    this.authorRole = 'Security Team',
    this.controls = const [],
    this.threats = const [],
    this.encryptionAlgorithms = const [],
    this.complianceFrameworks = const ['OWASP MASVS', 'DPDP Act 2023'],
    this.lastAuditDate,
    this.nextAuditDate,
  });

  /// Number of security controls.
  int get controlCount => controls.length;

  /// Number of threats modeled.
  int get threatCount => threats.length;

  /// Active security controls.
  List<SecurityControl> get activeControls =>
      controls.where((c) => c.isActive).toList();

  /// Mitigated threats.
  List<ThreatModelEntry> get mitigatedThreats =>
      threats.where((t) => t.isMitigated).toList();

  /// Unmitigated threats (risk items).
  List<ThreatModelEntry> get unmitigatedThreats =>
      threats.where((t) => !t.isMitigated).toList();

  /// Controls by category.
  List<SecurityControl> controlsByCategory(SecurityControlCategory category) =>
      controls.where((c) => c.category == category).toList();

  /// Controls covering a specific OWASP domain.
  List<SecurityControl> controlsForOwasp(OwaspDomain domain) =>
      controls.where((c) => c.owaspDomains.contains(domain)).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityWhitepaper &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(appName, version);
}
