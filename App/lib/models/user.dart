import 'dart:convert';

class UserModel {
  final String id;
  final String name;
  final String rollNumber;
  final String? email;
  final String? department;
  final String? profileUrl;
  final String? mobileNo; // Additional field for mobile number
  final String? aadhaar; // Additional field for Aadhaar number
  final String? enrollmentNo;
  final String? apaarId;
  final String? address;
  final String? category;
  final String? gender;
  final String? fatherName;
  final String? motherName;
  final String? semester;
  final String? dob;


  UserModel({
    required this.id,
    required this.name,
    required this.rollNumber,
    this.email,
    this.department,
    this.profileUrl,
    this.mobileNo,
    this.aadhaar,
    this.enrollmentNo,
    this.apaarId,
    this.address,
    this.category,
    this.gender,
    this.fatherName,
    this.motherName,
    this.semester, 
    required this.dob,

  });

  // 💡 Convert a Database Map (PostgreSQL Row) into a structured Dart object
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      rollNumber: map['roll_number']?.toString() ?? '',
      email: map['email']?.toString(),
      department: map['department']?.toString(),
      profileUrl: map['profile_url']?.toString(),
      mobileNo: map['Mobile_No']?.toString(),
      aadhaar: map['Aadhaar']?.toString(),
      enrollmentNo: map['enrollment_no']?.toString(),
      apaarId: map['apaar_id']?.toString(),
      address: map['address']?.toString(),
      category: map['category']?.toString(),
      gender: map['gender']?.toString(),
      fatherName: map['father_name']?.toString(),
      motherName: map['mother_name']?.toString(),
      semester: map['semester']?.toString(), 
      dob: map['dob']?.toString(),
    );
  }

  // 💡 Convert Dart object back into a Map for local JSON storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'roll_number': rollNumber,
      'email': email,
      'department': department,
      'profile_url': profileUrl,
      'Mobile_No': mobileNo,
      'Aadhaar': aadhaar,
      'enrollment_no': enrollmentNo,
      'apaar_id': apaarId,
      'address': address,
      'category': category,
      'gender': gender,
      'father_name': fatherName,
      'mother_name': motherName,
      'semester': semester,
      'dob': dob,
    };
  }

  // 💡 Serialization helpers to work seamlessly with SharedPreferences
  String toJson() => json.encode(toMap());

  factory UserModel.fromJson(String source) => UserModel.fromMap(json.decode(source));
}