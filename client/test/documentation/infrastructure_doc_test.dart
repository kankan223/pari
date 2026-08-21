import 'package:civic_commons/documentation/domain/infrastructure_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkZone', () {
    test('has 3 zones', () {
      expect(NetworkZone.values.length, 3);
    });

    test('labels are human-readable', () {
      expect(NetworkZone.private.label, 'Private');
      expect(NetworkZone.dmz.label, 'Dmz');
      expect(NetworkZone.public.label, 'Public');
    });
  });

  group('ComponentType', () {
    test('has 8 types', () {
      expect(ComponentType.values.length, 8);
    });

    test('labels are human-readable', () {
      expect(ComponentType.application.label, 'Application');
      expect(ComponentType.database.label, 'Database');
      expect(ComponentType.cache.label, 'Cache');
      expect(ComponentType.messageBroker.label, 'Message Broker');
      expect(ComponentType.objectStorage.label, 'Object Storage');
      expect(ComponentType.apiGateway.label, 'API Gateway');
      expect(ComponentType.cdn.label, 'CDN');
      expect(ComponentType.secretsManager.label, 'Secrets Manager');
    });
  });

  group('ComponentHealth', () {
    test('has 4 statuses', () {
      expect(ComponentHealth.values.length, 4);
    });

    test('labels are human-readable', () {
      expect(ComponentHealth.healthy.label, 'Healthy');
      expect(ComponentHealth.degraded.label, 'Degraded');
      expect(ComponentHealth.unhealthy.label, 'Unhealthy');
      expect(ComponentHealth.unknown.label, 'Unknown');
    });

    test('needsAttention for degraded and unhealthy', () {
      expect(ComponentHealth.healthy.needsAttention, false);
      expect(ComponentHealth.degraded.needsAttention, true);
      expect(ComponentHealth.unhealthy.needsAttention, true);
      expect(ComponentHealth.unknown.needsAttention, false);
    });
  });

  group('InfrastructureComponent', () {
    test('constructs with required fields', () {
      final component = InfrastructureComponent(
        id: 'postgres-primary',
        name: 'PostgreSQL Primary',
        type: ComponentType.database,
      );
      expect(component.id, 'postgres-primary');
      expect(component.networkZone, NetworkZone.private);
      expect(component.replicas, 1);
      expect(component.dependencies, isEmpty);
    });

    test('isRedundant with multiple replicas', () {
      final single = InfrastructureComponent(
          id: 'a', name: 'A', type: ComponentType.cache, replicas: 1);
      final multi = InfrastructureComponent(
          id: 'b', name: 'B', type: ComponentType.cache, replicas: 3);
      expect(single.isRedundant, false);
      expect(multi.isRedundant, true);
    });

    test('default network zone is private', () {
      final component = InfrastructureComponent(
          id: 'db', name: 'DB', type: ComponentType.database);
      expect(component.networkZone, NetworkZone.private);
    });

    test('explicit network zone is preserved', () {
      final component = InfrastructureComponent(
          id: 'gateway',
          name: 'Gateway',
          type: ComponentType.apiGateway,
          networkZone: NetworkZone.dmz);
      expect(component.networkZone, NetworkZone.dmz);
    });

    test('equality by id', () {
      final a = InfrastructureComponent(
          id: 'c1', name: 'C1', type: ComponentType.database);
      final b = InfrastructureComponent(
          id: 'c1', name: 'C2', type: ComponentType.cache);
      final c = InfrastructureComponent(
          id: 'c2', name: 'C1', type: ComponentType.database);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('CapacityPlan', () {
    test('constructs with defaults', () {
      final plan = CapacityPlan(componentId: 'db1');
      expect(plan.componentId, 'db1');
      expect(plan.currentUsagePercent, 0);
      expect(plan.currentReplicas, 1);
    });

    test('scalingRecommended when usage exceeds threshold', () {
      final ok = CapacityPlan(
          componentId: 'db1',
          currentUsagePercent: 50,
          scaleUpThresholdPercent: 70);
      final scale = CapacityPlan(
          componentId: 'db1',
          currentUsagePercent: 75,
          scaleUpThresholdPercent: 70);
      expect(ok.scalingRecommended, false);
      expect(scale.scalingRecommended, true);
    });

    test('isCritical when usage exceeds max threshold', () {
      final ok = CapacityPlan(
          componentId: 'db1',
          currentUsagePercent: 75,
          maxThresholdPercent: 80);
      final critical = CapacityPlan(
          componentId: 'db1',
          currentUsagePercent: 85,
          maxThresholdPercent: 80);
      expect(ok.isCritical, false);
      expect(critical.isCritical, true);
    });

    test('storageUsagePercent calculates correctly', () {
      final plan = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: 75,
          storageCapacityGb: 100);
      expect(plan.storageUsagePercent, 75);
    });

    test('storageUsagePercent is 0 when capacity is 0', () {
      final plan = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: 10,
          storageCapacityGb: 0);
      expect(plan.storageUsagePercent, 0);
    });

    test('storageNeedsAttention at 80% or above', () {
      final ok = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: 79,
          storageCapacityGb: 100);
      final warn = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: 80,
          storageCapacityGb: 100);
      expect(ok.storageNeedsAttention, false);
      expect(warn.storageNeedsAttention, true);
    });

    test('storageUsagePercent clamps to 0-100 range', () {
      // Over-capacity: should clamp to 100
      final over = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: 150,
          storageCapacityGb: 100);
      expect(over.storageUsagePercent, 100);
      // Negative usage: should clamp to 0
      final negative = CapacityPlan(
          componentId: 'db1',
          storageUsageGb: -10,
          storageCapacityGb: 100);
      expect(negative.storageUsagePercent, 0);
    });

    test('equality by componentId', () {
      final a = CapacityPlan(componentId: 'c1', currentUsagePercent: 50);
      final b = CapacityPlan(componentId: 'c1', currentUsagePercent: 90);
      final c = CapacityPlan(componentId: 'c2', currentUsagePercent: 50);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('MaintenanceWindow', () {
    test('constructs with required fields', () {
      final window = MaintenanceWindow(
        id: 'mw-001',
        description: 'Database upgrade',
        scheduledStart: '2026-08-21T02:00:00Z',
        scheduledEnd: '2026-08-21T04:00:00Z',
        affectedComponents: ['postgres-primary', 'postgres-replica'],
      );
      expect(window.id, 'mw-001');
      expect(window.affectedComponentCount, 2);
    });

    test('equality by id', () {
      final a = MaintenanceWindow(
          id: 'mw1',
          description: 'A',
          scheduledStart: '2026-08-21T02:00:00Z',
          scheduledEnd: '2026-08-21T04:00:00Z');
      final b = MaintenanceWindow(
          id: 'mw1',
          description: 'B',
          scheduledStart: '2026-08-22T02:00:00Z',
          scheduledEnd: '2026-08-22T04:00:00Z');
      final c = MaintenanceWindow(
          id: 'mw2',
          description: 'A',
          scheduledStart: '2026-08-21T02:00:00Z',
          scheduledEnd: '2026-08-21T04:00:00Z');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('InfrastructureDoc', () {
    test('constructs with components and plans', () {
      final components = [
        InfrastructureComponent(
            id: 'db', name: 'DB', type: ComponentType.database),
        InfrastructureComponent(
            id: 'cache', name: 'Cache', type: ComponentType.cache),
      ];
      final plans = [
        CapacityPlan(componentId: 'db', currentUsagePercent: 60),
      ];
      final doc = InfrastructureDoc(
        systemName: 'Civic Commons',
        components: components,
        capacityPlans: plans,
      );
      expect(doc.componentCount, 2);
      expect(doc.capacityPlans.length, 1);
    });

    test('getComponent returns matching component', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        components: [
          InfrastructureComponent(
              id: 'db', name: 'DB', type: ComponentType.database),
        ],
      );
      expect(doc.getComponent('db'), isNotNull);
      expect(doc.getComponent('missing'), isNull);
    });

    test('getComponentsByType filters correctly', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        components: [
          InfrastructureComponent(
              id: 'db1', name: 'DB1', type: ComponentType.database),
          InfrastructureComponent(
              id: 'db2', name: 'DB2', type: ComponentType.database),
          InfrastructureComponent(
              id: 'cache', name: 'Cache', type: ComponentType.cache),
        ],
      );
      expect(doc.getComponentsByType(ComponentType.database).length, 2);
      expect(doc.getComponentsByType(ComponentType.cache).length, 1);
      expect(doc.getComponentsByType(ComponentType.cdn).length, 0);
    });

    test('getCapacityPlan returns matching plan', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        capacityPlans: [
          CapacityPlan(
              componentId: 'db', currentUsagePercent: 75),
        ],
      );
      expect(doc.getCapacityPlan('db'), isNotNull);
      expect(doc.getCapacityPlan('missing'), isNull);
    });

    test('scalingRecommended returns plans needing scale', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        capacityPlans: [
          CapacityPlan(
              componentId: 'db',
              currentUsagePercent: 80,
              scaleUpThresholdPercent: 70),
          CapacityPlan(
              componentId: 'cache',
              currentUsagePercent: 30,
              scaleUpThresholdPercent: 70),
        ],
      );
      expect(doc.scalingRecommended.length, 1);
      expect(doc.scalingRecommended.first.componentId, 'db');
    });

    test('criticalCapacity returns plans at max threshold', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        capacityPlans: [
          CapacityPlan(
              componentId: 'db',
              currentUsagePercent: 90,
              maxThresholdPercent: 80),
          CapacityPlan(
              componentId: 'cache',
              currentUsagePercent: 50,
              maxThresholdPercent: 80),
        ],
      );
      expect(doc.criticalCapacity.length, 1);
      expect(doc.criticalCapacity.first.componentId, 'db');
    });

    test('componentTypes returns unique types', () {
      final doc = InfrastructureDoc(
        systemName: 'S',
        components: [
          InfrastructureComponent(
              id: 'db', name: 'DB', type: ComponentType.database),
          InfrastructureComponent(
              id: 'db2', name: 'DB2', type: ComponentType.database),
          InfrastructureComponent(
              id: 'cache', name: 'Cache', type: ComponentType.cache),
        ],
      );
      expect(doc.componentTypes.length, 2);
      expect(doc.componentTypes, contains(ComponentType.database));
      expect(doc.componentTypes, contains(ComponentType.cache));
    });

    test('equality by systemName', () {
      final a = InfrastructureDoc(systemName: 'S1');
      final b = InfrastructureDoc(systemName: 'S1');
      final c = InfrastructureDoc(systemName: 'S2');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('PII audit', () {
    test('infrastructure labels have zero PII patterns', () {
      for (final type in ComponentType.values) {
        expect(type.label, isNot(contains('+')));
        expect(type.label, isNot(contains('@')));
      }
      for (final health in ComponentHealth.values) {
        expect(health.label, isNot(contains('+')));
        expect(health.label, isNot(contains('@')));
      }
    });
  });
}
