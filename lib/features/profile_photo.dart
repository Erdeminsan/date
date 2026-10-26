import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../backend/repository.dart';
import '../backend/photo_processing.dart';

class ProfilePhoto extends StatefulWidget {
  const ProfilePhoto({super.key, required this.backend, this.path, this.size = 48});
  final Backend backend;
  final String? path;
  final double size;
  @override
  State<ProfilePhoto> createState() => _ProfilePhotoState();
}
class _ProfilePhotoState extends State<ProfilePhoto> {
  Future<Uint8List>? bytes;
  @override
  void initState() { super.initState(); load(); }
  @override
  void didUpdateWidget(ProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.backend != widget.backend) load();
  }
  void load() { bytes = widget.path == null ? null : widget.backend.downloadPhoto(widget.path!); }
  @override
  Widget build(BuildContext context) => ClipOval(child: SizedBox(
    width: widget.size, height: widget.size,
    child: bytes == null ? const ColoredBox(color: Color(0xFF45415E), child: Icon(Icons.person_outline))
      : FutureBuilder<Uint8List>(future: bytes, builder: (context, snapshot) {
        if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover, cacheWidth: 256,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
        if (snapshot.hasError) return IconButton(tooltip: 'Fotoğrafı tekrar yükle', onPressed: () => setState(load), icon: const Icon(Icons.refresh));
        return const Center(child: SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)));
      }),
  ));
}

class ProfilePhotoEditor extends StatefulWidget {
  const ProfilePhotoEditor({super.key, required this.backend, this.initialPath});
  final Backend backend;
  final String? initialPath;
  @override
  State<ProfilePhotoEditor> createState() => _ProfilePhotoEditorState();
}
class _ProfilePhotoEditorState extends State<ProfilePhotoEditor> {
  String? path, notice;
  bool busy = false;
  @override
  void initState() { super.initState(); path = widget.initialPath; }
  @override
  void didUpdateWidget(ProfilePhotoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPath != widget.initialPath) path = widget.initialPath;
  }
  Future<void> change() async {
    if (busy) return;
    final owner = widget.backend.userId;
    setState(() { busy = true; notice = null; });
    try {
      final selected = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 90, requestFullMetadata: false);
      if (selected == null) return;
      if (await selected.length() > 12*1024*1024) throw const FormatException('Fotoğraf çok büyük.');
      final data = await compute(prepareProfilePhoto, await selected.readAsBytes());
      final uploaded = await widget.backend.uploadPhoto(data, expectedUserId: owner);
      if (mounted) setState(() { path = uploaded; notice = 'Profil fotoğrafın kaydedildi.'; });
    } on FormatException catch (e) {
      if (mounted) setState(() => notice = e.message);
    } catch (e) {
      if (mounted) setState(() => notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> remove() async {
    if (busy) return;
    final owner = widget.backend.userId;
    final confirmed = await showDialog<bool>(useRootNavigator: false, context: context, builder: (context) => AlertDialog(
      title: const Text('Profil fotoğrafını sil?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context,true), child: const Text('Sil'))],
    ));
    if (confirmed != true || !mounted || busy) return;
    setState(() { busy = true; notice = null; });
    try {
      await widget.backend.removePhoto(expectedUserId: owner);
      if (mounted) setState(() { path = null; notice = 'Profil fotoğrafın silindi.'; });
    } catch (e) {
      if (mounted) setState(() => notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    ProfilePhoto(backend: widget.backend,path: path,size: 112),
    const SizedBox(height: 8),
    const Text('Fotoğrafın, profilini görebilen kişilere gösterilir.'),
    TextButton(onPressed: busy ? null : change, child: Text(busy ? 'İşleniyor…' : 'Fotoğraf seç / değiştir')),
    TextButton(onPressed: busy ? null : remove, child: const Text('Fotoğrafı sil')),
    if (notice != null) Text(notice!),
    const SizedBox(height: 24),
  ]);
}
