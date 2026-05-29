import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/sync/offline_sync_service.dart';

class PatientWithProgrammes {
  const PatientWithProgrammes(this.patient, this.programmes);
  final Patient patient;
  final Set<Programme> programmes;
}

class PatientRepository {
  PatientRepository({
    required PatientDao patients,
    required PatientProgrammesDao programmes,
    required OfflineSyncService sync,
  })  : _patients = patients,
        _programmes = programmes,
        _sync = sync;

  final PatientDao _patients;
  final PatientProgrammesDao _programmes;
  final OfflineSyncService _sync;

  /// Returns the cached patient; if absent, attempts a granular refresh
  /// before reading again. Returns null when the patient is unknown locally
  /// AND the server lookup fails.
  Future<PatientWithProgrammes?> byId(String id) async {
    var p = await _patients.byId(id);
    if (p == null) {
      await _sync.refreshPatient(id);
      p = await _patients.byId(id);
      if (p == null) return null;
    }
    final progs = await _programmes.programmesFor(id);
    return PatientWithProgrammes(p, progs);
  }

  /// Force a remote refresh for the patient and re-read locally.
  Future<PatientWithProgrammes?> refresh(String id) async {
    await _sync.refreshPatient(id);
    final p = await _patients.byId(id);
    if (p == null) return null;
    final progs = await _programmes.programmesFor(id);
    return PatientWithProgrammes(p, progs);
  }
}
