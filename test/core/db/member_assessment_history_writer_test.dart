import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/member_assessment_history_writer.dart';

void main() {
  group('MemberAssessmentHistoryWriter.wireServiceProvided', () {
    test('maps eye wire tags to eye_care', () {
      expect(MemberAssessmentHistoryWriter.wireServiceProvided('EYE_CARE'),
          'eye_care');
      expect(MemberAssessmentHistoryWriter.wireServiceProvided('EYECARE'),
          'eye_care');
      expect(
        MemberAssessmentHistoryWriter.wireServiceProvided('eye-care'),
        'eye_care',
      );
    });
  });
}
