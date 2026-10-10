import 'package:json_annotation/json_annotation.dart';

part 'login_request_model.g.dart';

@JsonSerializable()
class LoginRequestModel {
  final String phone;
  final String password; // ← Changed from 'pin' to 'password'
  @JsonKey(name: 'remember_me', defaultValue: false)
  final bool rememberMe;

  const LoginRequestModel({
    required this.phone,
    required this.password, // ← Changed
    this.rememberMe = false,
  });

  factory LoginRequestModel.fromJson(Map<String, dynamic> json) =>
      _$LoginRequestModelFromJson(json);

  Map<String, dynamic> toJson() => _$LoginRequestModelToJson(this);
}
