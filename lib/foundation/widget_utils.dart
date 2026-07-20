import 'package:flutter/widgets.dart';
import 'package:kong_comic/foundation/text_styles.dart';

extension WidgetExtension on Widget{
  Widget padding(EdgeInsetsGeometry padding){
    return Padding(padding: padding, child: this);
  }

  Widget paddingLeft(double padding){
    return Padding(padding: EdgeInsets.only(left: padding), child: this);
  }

  Widget paddingRight(double padding){
    return Padding(padding: EdgeInsets.only(right: padding), child: this);
  }

  Widget paddingTop(double padding){
    return Padding(padding: EdgeInsets.only(top: padding), child: this);
  }

  Widget paddingBottom(double padding){
    return Padding(padding: EdgeInsets.only(bottom: padding), child: this);
  }

  Widget paddingVertical(double padding){
    return Padding(padding: EdgeInsets.symmetric(vertical: padding), child: this);
  }

  Widget paddingHorizontal(double padding){
    return Padding(padding: EdgeInsets.symmetric(horizontal: padding), child: this);
  }

  Widget paddingAll(double padding){
    return Padding(padding: EdgeInsets.all(padding), child: this);
  }

  Widget toCenter(){
    return Center(child: this);
  }

  Widget toAlign(AlignmentGeometry alignment){
    return Align(alignment: alignment, child: this);
  }

  Widget sliverPadding(EdgeInsetsGeometry padding){
    return SliverPadding(padding: padding, sliver: this);
  }

  Widget sliverPaddingAll(double padding){
    return SliverPadding(padding: EdgeInsets.all(padding), sliver: this);
  }

  Widget sliverPaddingVertical(double padding){
    return SliverPadding(padding: EdgeInsets.symmetric(vertical: padding), sliver: this);
  }

  Widget sliverPaddingHorizontal(double padding){
    return SliverPadding(padding: EdgeInsets.symmetric(horizontal: padding), sliver: this);
  }

  Widget fixWidth(double width){
    return SizedBox(width: width, child: this);
  }

  Widget fixHeight(double height){
    return SizedBox(height: height, child: this);
  }

  Widget toSliver(){
    return SliverToBoxAdapter(child: this);
  }
}

/// create default text style
TextStyle get ts => const TextStyle();

extension StyledText on TextStyle {
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);

  TextStyle get light => copyWith(fontWeight: FontWeight.w300);

  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);

  TextStyle get underline => copyWith(decoration: TextDecoration.underline);

  TextStyle get lineThrough => copyWith(decoration: TextDecoration.lineThrough);

  TextStyle get overline => copyWith(decoration: TextDecoration.overline);

  TextStyle get s8 => copyWith(fontSize: AppFontSizes.s8);

  TextStyle get s10 => copyWith(fontSize: AppFontSizes.s10);

  TextStyle get s12 => copyWith(fontSize: AppFontSizes.s12);

  TextStyle get s14 => copyWith(fontSize: AppFontSizes.s14);

  TextStyle get s16 => copyWith(fontSize: AppFontSizes.s16);

  TextStyle get s18 => copyWith(fontSize: AppFontSizes.s18);

  TextStyle get s20 => copyWith(fontSize: AppFontSizes.s20);

  TextStyle get s24 => copyWith(fontSize: AppFontSizes.s24);

  TextStyle get s28 => copyWith(fontSize: AppFontSizes.s28);

  TextStyle get s32 => copyWith(fontSize: AppFontSizes.s32);

  TextStyle get s36 => copyWith(fontSize: AppFontSizes.s36);

  TextStyle get s40 => copyWith(fontSize: AppFontSizes.s40);

  TextStyle withColor(Color? color) => copyWith(color: color);
}

extension ColorExt on Color {
  Color toOpacity(double opacity) {
    return withValues(alpha: opacity);
  }
}