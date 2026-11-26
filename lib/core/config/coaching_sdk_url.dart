/// Base URL the micro-coaching SDK (Retrofit) actually uses.
///
/// Retrofit requires the base URL to end with '/' and include the full path
/// prefix. `AppConfig.coachingServiceUrl` omits 'medtronics-api/' for Dio
/// callers, so it is normalized here.
String coachingSdkBaseUrl(String url) {
  var u = url.endsWith('/') ? url : '$url/';
  if (!u.contains('medtronics-api')) u = '${u}medtronics-api/';
  return u;
}
