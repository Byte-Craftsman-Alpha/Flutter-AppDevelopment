import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class RichChatMessageParser extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;

  const RichChatMessageParser({
    super.key,
    required this.text,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    // Splits text matching standard LaTeX markers safely
    final RegExp mathRegex = RegExp(r'(\$\$(.*?)\$\$)|(\$(.*?)\$)');
    
    final List<String> segments = [];
    final Iterable<RegExpMatch> matches = mathRegex.allMatches(text);
    
    int lastIndex = 0;
    
    for (final match in matches) {
      if (match.start > lastIndex) {
        segments.add(text.substring(lastIndex, match.start));
      }
      segments.add(match.group(0)!);
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      segments.add(text.substring(lastIndex));
    }

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: segments.map((chunk) {
        // Block LaTeX equation processing
        if (chunk.startsWith('\$\$') && chunk.endsWith('\$\$')) {
          final expression = chunk.substring(2, chunk.length - 2);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Math.tex(
                  expression,
                  mathStyle: MathStyle.display,
                  textStyle: baseStyle?.copyWith(fontSize: 15),
                ),
              ),
            ),
          );
        } 
        // Inline LaTeX formula processing
        else if (chunk.startsWith('\$') && chunk.endsWith('\$')) {
          final expression = chunk.substring(1, chunk.length - 1);
          return Math.tex(
            expression,
            mathStyle: MathStyle.text,
            textStyle: baseStyle?.copyWith(fontSize: 14),
          );
        } 
        // Standard Text / Markdown processing
        else {
          return MarkdownBody(
            data: chunk,
            shrinkWrap: true,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: baseStyle ?? TextStyle(color: Colors.grey.shade900, fontSize: 14, height: 1.3),
              em: const TextStyle(fontStyle: FontStyle.italic),
              strong: const TextStyle(fontWeight: FontWeight.bold),
              del: const TextStyle(decoration: TextDecoration.lineThrough),
            ),
          );
        }
      }).toList(),
    );
  }
}