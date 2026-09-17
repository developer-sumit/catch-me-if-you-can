enum UserRole { kitchen, ngo }

class User {
  const User(
      {required this.id,
      required this.name,
      required this.email,
      required this.role,
      required this.organization,
      this.phone = '',
      this.address = '',
      this.latitude,
      this.longitude});
  final String id, name, email, organization, phone, address;
  final UserRole role;
  final double? latitude, longitude;
  factory User.fromJson(Map<String, dynamic> j) => User(
      id: j['id'],
      name: j['name'],
      email: j['email'],
      role: j['role'] == 'ngo' ? UserRole.ngo : UserRole.kitchen,
      organization: j['organization'] ?? '',
      phone: j['phone'] ?? '',
      address: j['address'] ?? '',
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble());
}
