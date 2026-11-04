/// لیستی از Map ها را از JSON بیرون می‌کشد (موارد نامعتبر نادیده گرفته می‌شوند).
List<Map<String, dynamic>> mapList(dynamic v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
