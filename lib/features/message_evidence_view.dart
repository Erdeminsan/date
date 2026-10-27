import 'package:flutter/material.dart';
import '../backend/repository.dart';

class MessageEvidenceView extends StatelessWidget {
  const MessageEvidenceView({super.key,required this.evidence});
  final MessageEvidence evidence;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8),child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,children: [
      const Text('Şikâyete eklenen mesaj',style: TextStyle(fontWeight: FontWeight.bold)),
      SelectableText(evidence.body),
      Text('Gönderilme: ${evidence.sentAt.toLocal()}'),
      Text('Kayıt zamanı: ${evidence.capturedAt.toLocal()}'),
    ],
  ));
}
