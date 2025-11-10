import 'package:flutter/material.dart';
import 'main.dart';

class ManageAccountScreen extends StatelessWidget {
  const ManageAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Account'),
      ),
      body: Stack(
        children: [
          // Wave background
          SizedBox.expand(
            child: Image.asset(
              'assets/images/main_waves.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _accountField("Username", icon: Icons.person),
                _accountField("Email", icon: Icons.email),
                _accountField("Password", obscure: true, icon: Icons.lock),
                const SizedBox(height: 24),
                gradientButton(
                  text: 'Change Password',
                  onPressed: () {},
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountField(String label, {bool obscure = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.white.withOpacity(0.7))
              : null,
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
        ),
      ),
    );
  }
}
