import 'package:flutter/material.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;
  final bool isCircle;

  const GradientButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
    this.borderRadius = 12,
    this.fontSize = 16,
    this.isCircle = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onPressed,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Ink(
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? const LinearGradient(
                  colors: [Colors.grey, Colors.grey],
                )
              : const LinearGradient(
                  colors: [Color(0xFFDE0E6F), Color.fromARGB(255, 216, 221, 224)],
                ),
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        ),
        child: Container(
          padding: padding,
          alignment: Alignment.center,
          child: isLoading
              ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                )
              : Text(
                  text,
                  style: TextStyle(color: Colors.white, fontSize: fontSize),
                ),
        ),
      ),
    );
  }
}
