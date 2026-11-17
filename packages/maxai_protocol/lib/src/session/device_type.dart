/// Тип устройства, передаваемый в SESSION_INIT.
enum DeviceType {
  web('WEB'),
  android('ANDROID'),
  ios('IOS'),
  desktop('DESKTOP');

  const DeviceType(this.value);
  final String value;
}
