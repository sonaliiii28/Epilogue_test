import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared constants – match the app‑wide purple palette.
const _violetAccent = Color(0xFF7A64A4);
const _idleBorder = Color(0xFFD4CDDF);
const _deepPurple = Color(0xFF443C63);
const _hintColor = Color(0xFFB8B0CC);
const _mutedPurple = Color(0xFF6C648B);

/// A text‑input field whose border smoothly animates to violet on focus.
///
/// Drop‑in replacement for any plain `TextField` / `TextFormField` across the
/// app.  Supports prefixIcon, suffixIcon, multi‑line, maxLength, inputFormatters,
/// obscureText, readOnly, onChanged, onSubmitted, validator, etc.
class AnimatedBorderField extends StatefulWidget {
  const AnimatedBorderField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.readOnly = false,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.inputFormatters,
    this.borderRadius = 14,
    this.fontSize = 14,
    this.counterStyle,
    this.contentPadding,
    this.validator,
    this.textHeight,
  });

  final TextEditingController controller;
  final String? hint;
  final String? label;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool readOnly;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final double borderRadius;
  final double fontSize;
  final TextStyle? counterStyle;
  final EdgeInsetsGeometry? contentPadding;
  final String? Function(String?)? validator;
  final double? textHeight;

  @override
  State<AnimatedBorderField> createState() => _AnimatedBorderFieldState();
}

class _AnimatedBorderFieldState extends State<AnimatedBorderField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Color?> _borderTween;
  late final FocusNode _internalFocus;
  bool _focused = false;

  FocusNode get _effectiveFocus => widget.focusNode ?? _internalFocus;

  @override
  void initState() {
    super.initState();
    _internalFocus = FocusNode();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _borderTween = ColorTween(
      begin: _idleBorder,
      end: _violetAccent,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    if (widget.focusNode == null) _internalFocus.dispose();
    super.dispose();
  }

  void _handleFocus(bool focused) {
    setState(() => _focused = focused);
    focused ? _anim.forward() : _anim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final pad =
        widget.contentPadding ??
        EdgeInsets.symmetric(
          horizontal: widget.prefixIcon != null ? 0 : 14,
          vertical: 14,
        );

    return Focus(
      focusNode: _effectiveFocus,
      onFocusChange: _handleFocus,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_focused ? 0.95 : 0.8),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _borderTween.value ?? _idleBorder,
                width: _focused ? 1.8 : 1.0,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: _violetAccent.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: child,
          );
        },
        child: _buildInput(pad),
      ),
    );
  }

  Widget _buildInput(EdgeInsetsGeometry pad) {
    final style = GoogleFonts.nunito(
      fontSize: widget.fontSize,
      color: _deepPurple,
      fontWeight: FontWeight.w500,
      height: widget.textHeight,
    );

    final decoration = InputDecoration(
      hintText: widget.hint,
      labelText: widget.label,
      hintStyle: GoogleFonts.nunito(
        fontSize: widget.fontSize,
        color: _hintColor,
      ),
      prefixIcon: widget.prefixIcon != null
          ? Icon(widget.prefixIcon, size: 18, color: _mutedPurple)
          : null,
      suffixIcon: widget.suffixIcon,
      border: InputBorder.none,
      counterText: widget.maxLength != null ? '' : null,
      counterStyle: widget.counterStyle,
      contentPadding: pad,
    );

    if (widget.validator != null) {
      return TextFormField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        readOnly: widget.readOnly,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        style: style,
        validator: widget.validator,
        decoration: decoration,
      );
    }

    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      readOnly: widget.readOnly,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: style,
      decoration: decoration,
    );
  }
}
