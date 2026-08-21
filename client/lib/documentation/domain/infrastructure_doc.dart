/// Infrastructure documentation domain models (Task 15.2).
///
/// Defines system architecture, component relationships, capacity
/// planning, and maintenance schedules. All values are pure — no
/// identity, no PII, no secrets, no credentials.

/// Network zone for infrastructure components.
enum NetworkZone {
  /// Private network, not accessible from internet.
  private,

  /// DMZ, accessible from both internal and external networks.
  dmz,

  /// Public network, accessible from internet.
  public;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Type of infrastructure component.
enum ComponentType {
  /// Application server.
  application,

  /// Database instance.
  database,

  /// Cache layer.
  cache,

  /// Message broker.
  messageBroker,

  /// Object storage.
  objectStorage,

  /// API gateway.
  apiGateway,

  /// CDN edge node.
  cdn,

  /// Secrets manager.
  secretsManager;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ComponentType.application:
        return 'Application';
      case ComponentType.database:
        return 'Database';
      case ComponentType.cache:
        return 'Cache';
      case ComponentType.messageBroker:
        return 'Message Broker';
      case ComponentType.objectStorage:
        return 'Object Storage';
      case ComponentType.apiGateway:
        return 'API Gateway';
      case ComponentType.cdn:
        return 'CDN';
      case ComponentType.secretsManager:
        return 'Secrets Manager';
    }
  }
}

/// Health status of an infrastructure component.
enum ComponentHealth {
  /// Component is operating normally.
  healthy,

  /// Component is degraded but operational.
  degraded,

  /// Component is not responding.
  unhealthy,

  /// Component status is unknown.
  unknown;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ComponentHealth.healthy:
        return 'Healthy';
      case ComponentHealth.degraded:
        return 'Degraded';
      case ComponentHealth.unhealthy:
        return 'Unhealthy';
      case ComponentHealth.unknown:
        return 'Unknown';
    }
  }

  /// Whether the component needs attention.
  bool get needsAttention =>
      this == ComponentHealth.degraded ||
      this == ComponentHealth.unhealthy;
}

/// A single infrastructure component.
class InfrastructureComponent {
  /// Unique identifier (e.g., 'postgres-primary').
  final String id;

  /// Human-readable name.
  final String name;

  /// Component type.
  final ComponentType type;

  /// Network zone.
  final NetworkZone networkZone;

  /// Number of replicas.
  final int replicas;

  /// Resource tier (e.g., 'small', 'medium', 'large', 'xlarge').
  final String resourceTier;

  /// Dependencies (other component IDs).
  final List<String> dependencies;

  /// Health check endpoint path.
  final String? healthCheckPath;

  /// Maximum concurrent connections.
  final int? maxConnections;

  const InfrastructureComponent({
    required this.id,
    required this.name,
    required this.type,
    this.networkZone = NetworkZone.private,
    this.replicas = 1,
    this.resourceTier = 'medium',
    this.dependencies = const [],
    this.healthCheckPath,
    this.maxConnections,
  });

  /// Whether this component is redundant (multiple replicas).
  bool get isRedundant => replicas > 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfrastructureComponent &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Capacity planning information for a component.
class CapacityPlan {
  /// Component ID this plan applies to.
  final String componentId;

  /// Current resource usage percentage (0-100).
  final int currentUsagePercent;

  /// Recommended maximum usage threshold.
  final int maxThresholdPercent;

  /// Recommended scale-up threshold.
  final int scaleUpThresholdPercent;

  /// Current replica count.
  final int currentReplicas;

  /// Recommended replica count.
  final int recommendedReplicas;

  /// Storage usage in GB.
  final double storageUsageGb;

  /// Maximum storage capacity in GB.
  final double storageCapacityGb;

  const CapacityPlan({
    required this.componentId,
    this.currentUsagePercent = 0,
    this.maxThresholdPercent = 80,
    this.scaleUpThresholdPercent = 70,
    this.currentReplicas = 1,
    this.recommendedReplicas = 1,
    this.storageUsageGb = 0,
    this.storageCapacityGb = 100,
  });

  /// Whether scaling is recommended.
  bool get scalingRecommended =>
      currentUsagePercent >= scaleUpThresholdPercent;

  /// Whether capacity is critically high.
  bool get isCritical => currentUsagePercent >= maxThresholdPercent;

  /// Storage usage percentage.
  int get storageUsagePercent {
    if (storageCapacityGb <= 0) return 0;
    final raw = ((storageUsageGb / storageCapacityGb) * 100).round();
    // Clamp to valid 0-100 range to prevent invalid state.
    if (raw < 0) return 0;
    if (raw > 100) return 100;
    return raw;
  }

  /// Whether storage needs attention.
  bool get storageNeedsAttention => storageUsagePercent >= 80;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapacityPlan &&
          runtimeType == other.runtimeType &&
          componentId == other.componentId;

  @override
  int get hashCode => componentId.hashCode;
}

/// A scheduled maintenance window.
class MaintenanceWindow {
  /// Unique identifier.
  final String id;

  /// Human-readable description of the maintenance.
  final String description;

  /// Scheduled start time (ISO 8601).
  final String scheduledStart;

  /// Scheduled end time (ISO 8601).
  final String scheduledEnd;

  /// Affected component IDs.
  final List<String> affectedComponents;

  /// Whether user notification is required.
  final bool requiresUserNotification;

  /// Whether a rollback plan is mandatory.
  final bool requiresRollbackPlan;

  const MaintenanceWindow({
    required this.id,
    required this.description,
    required this.scheduledStart,
    required this.scheduledEnd,
    this.affectedComponents = const [],
    this.requiresUserNotification = false,
    this.requiresRollbackPlan = false,
  });

  /// Number of affected components.
  int get affectedComponentCount => affectedComponents.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaintenanceWindow &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Complete infrastructure documentation for a system.
class InfrastructureDoc {
  /// Project or system name.
  final String systemName;

  /// All infrastructure components.
  final List<InfrastructureComponent> components;

  /// Capacity plans per component.
  final List<CapacityPlan> capacityPlans;

  /// Scheduled maintenance windows.
  final List<MaintenanceWindow> maintenanceWindows;

  const InfrastructureDoc({
    required this.systemName,
    this.components = const [],
    this.capacityPlans = const [],
    this.maintenanceWindows = const [],
  });

  /// Number of components.
  int get componentCount => components.length;

  /// Get component by ID.
  InfrastructureComponent? getComponent(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Get components by type.
  List<InfrastructureComponent> getComponentsByType(ComponentType type) =>
      components.where((c) => c.type == type).toList();

  /// Get capacity plan for a component.
  CapacityPlan? getCapacityPlan(String componentId) {
    for (final p in capacityPlans) {
      if (p.componentId == componentId) return p;
    }
    return null;
  }

  /// Components that need scaling.
  List<CapacityPlan> get scalingRecommended =>
      capacityPlans.where((p) => p.scalingRecommended).toList();

  /// Components at critical capacity.
  List<CapacityPlan> get criticalCapacity =>
      capacityPlans.where((p) => p.isCritical).toList();

  /// Upcoming maintenance windows.
  List<MaintenanceWindow> get upcomingMaintenance =>
      maintenanceWindows.toList();

  /// Component types present in the infrastructure.
  Set<ComponentType> get componentTypes =>
      components.map((c) => c.type).toSet();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfrastructureDoc &&
          runtimeType == other.runtimeType &&
          systemName == other.systemName;

  @override
  int get hashCode => systemName.hashCode;
}
