import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';

class PatientWithProgrammes {
  const PatientWithProgrammes(this.patient, this.programmes);
  final Patient patient;
  final Set<Programme> programmes;
}

class PatientRepository {
  PatientRepository({
    required PatientDao patients,
    required PatientProgrammesDao programmes,
  })  : _patients = patients,
        _programmes = programmes;

  final PatientDao _patients;
  final PatientProgrammesDao _programmes;

  /// Returns the patient from local cache. Patient data comes from
  /// offline-sync/fetch-synced-data; there is no granular remote refresh.
  Future<PatientWithProgrammes?> byId(String id) async {
    final p = await _patients.byId(id);
    if (p == null) return null;
    final progs = await _programmes.programmesFor(id);
    return PatientWithProgrammes(p, progs);
  }

  /// Re-read from local cache. Data is refreshed via the full sync cycle.
  Future<PatientWithProgrammes?> refresh(String id) => byId(id);
}
