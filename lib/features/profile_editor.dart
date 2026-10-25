import 'package:flutter/material.dart';
import '../backend/repository.dart';
import 'profile_photo.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.backend,
    required this.onSaved,
    this.initial,
  });
  final Backend backend;
  final OwnProfile? initial;
  final VoidCallback onSaved;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, city, interests;
  DateTime? birth;
  bool visible = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.person.name);
    city = TextEditingController(text: widget.initial?.city);
    interests = TextEditingController(text: widget.initial?.interests);
    birth = widget.initial?.birthDate;
    visible = widget.initial?.person.visible ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    city.dispose();
    interests.dispose();
    super.dispose();
  }

  Future<void> chooseBirth() async {
    final today = DateTime.now();
    final latest = DateTime(today.year - 18, today.month, today.day);
    final value = await showDatePicker(
      context: context,
      initialDate: birth ?? DateTime(today.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: latest,
      helpText: 'Doğum tarihin',
    );
    if (mounted && value != null) setState(() => birth = value);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (birth == null || !isAdult(birth!, DateTime.now())) {
      setState(
        () => error = '18 yaş ve üzeri olduğunu gösteren doğum tarihini seç.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.backend.saveProfile(
        name: name.text,
        birthDate: birth!,
        city: city.text,
        interests: interests.text,
        visible: visible,
      );
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (widget.initial != null) ProfilePhotoEditor(backend: widget.backend, initialPath: widget.initial!.person.photoPath),
        Text(
          widget.initial == null ? 'Seni biraz tanıyalım.' : 'Profilin',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Adın keşfette görünür. Doğum tarihin, şehrin ve ilgi alanların bu sürümde yalnızca sana açıktır.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: name,
          enabled: !busy,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Görünen ad'),
          validator:
              (v) =>
                  (v ?? '').trim().length < 2 ? 'En az 2 karakter gir.' : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Doğum tarihi'),
          subtitle: Text(
            birth == null
                ? 'Tarih seç'
                : '${birth!.day}.${birth!.month}.${birth!.year}',
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: busy || widget.initial != null ? null : chooseBirth,
        ),
        if (widget.initial != null)
          const Text(
            'Doğum tarihi sonradan değiştirilemez.',
            style: TextStyle(color: Colors.white60),
          ),
        const SizedBox(height: 16),
        TextFormField(
          controller: city,
          enabled: !busy,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Şehir'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Şehrini gir.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: interests,
          enabled: !busy,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'İlgi alanların'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keşfette görün'),
          value: visible,
          subtitle: const Text(
            'Kapalıyken yeni beğeni gönderemez veya alamazsın.',
          ),
          onChanged: busy ? null : (v) => setState(() => visible = v),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!),
          ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Kaydediliyor…' : 'Profili kaydet'),
        ),
      ],
    ),
  );
}
