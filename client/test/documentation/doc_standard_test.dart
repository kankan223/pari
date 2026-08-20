import 'package:civic_commons/documentation/domain/doc_standard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.1 — Documentation Standards', () {
    group('DocFormat', () {
      test('has all formats', () {
        expect(DocFormat.values.length, 3);
        expect(DocFormat.values, contains(DocFormat.dartDoc));
        expect(DocFormat.values, contains(DocFormat.goDoc));
        expect(DocFormat.values, contains(DocFormat.markdown));
      });

      test('label returns human-readable name', () {
        expect(DocFormat.dartDoc.label, 'Dart Doc');
        expect(DocFormat.goDoc.label, 'Go Doc');
        expect(DocFormat.markdown.label, 'Markdown');
      });
    });

    group('DocRequirement', () {
      test('constructs with required fields', () {
        const req = DocRequirement(
          elementType: 'class',
          required: true,
          sections: ['Description', 'Parameters', 'Returns'],
        );
        expect(req.elementType, 'class');
        expect(req.required, isTrue);
        expect(req.sections.length, 3);
      });

      test('equality by element type', () {
        const a = DocRequirement(elementType: 'class');
        const b = DocRequirement(elementType: 'class', required: false);
        const c = DocRequirement(elementType: 'function');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('DocStandard', () {
      test('constructs with defaults', () {
        const standard = DocStandard(
          projectName: 'Civic Commons',
        );
        expect(standard.projectName, 'Civic Commons');
        expect(standard.format, DocFormat.dartDoc);
        expect(standard.minCoveragePercent, 80);
        expect(standard.autoGenerateApiDocs, isTrue);
        expect(standard.maxLineLength, 80);
      });

      test('requirementFor returns correct requirement', () {
        const standard = DocStandard(
          projectName: 'Test',
          requirements: [
            DocRequirement(
              elementType: 'class',
              sections: ['Description'],
            ),
            DocRequirement(
              elementType: 'function',
              sections: ['Description', 'Parameters'],
            ),
          ],
        );
        expect(standard.requirementFor('class'), isNotNull);
        expect(standard.requirementFor('function'), isNotNull);
        expect(standard.requirementFor('enum'), isNull);
      });

      test('equality by project name and format', () {
        const a = DocStandard(projectName: 'Test', format: DocFormat.dartDoc);
        const b = DocStandard(projectName: 'Test', format: DocFormat.dartDoc);
        const c = DocStandard(projectName: 'Test', format: DocFormat.goDoc);
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in format labels', () {
        for (final format in DocFormat.values) {
          expect(format.label, isNot(contains('@')));
          expect(format.label, isNot(contains('+')));
          expect(format.label, isNot(contains('phone')));
          expect(format.label, isNot(contains('email')));
        }
      });

      test('no PII in element type strings', () {
        final types = ['class', 'function', 'enum', 'mixin', 'extension'];
        for (final type in types) {
          expect(type, isNot(contains(RegExp(r'[0-9]{10}'))));
          expect(type, isNot(contains('@')));
        }
      });
    });
  });
}
