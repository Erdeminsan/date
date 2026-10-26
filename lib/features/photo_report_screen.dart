import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../backend/repository.dart';

class PhotoReportScreen extends StatefulWidget {
  const PhotoReportScreen({super.key,required this.backend,required this.targetId,required this.path});
  final Backend backend;
  final String targetId,path;
  @override
  State<PhotoReportScreen> createState()=>_PhotoReportScreenState();
}
class _PhotoReportScreenState extends State<PhotoReportScreen> with WidgetsBindingObserver {
  late final String owner;
  final reason=TextEditingController();
  String requestId=newMessageRequestId();
  Uint8List? bytes;
  String? digest,pendingDigest,pendingReason,error;
  bool busy=false,loading=false,foreground=true;
  int generation=0;
  @override
  void initState(){super.initState();owner=widget.backend.userId;WidgetsBinding.instance.addObserver(this);load();}
  void clearImage(){if(bytes!=null)MemoryImage(bytes!).evict();bytes=null;digest=null;}
  Future<void> load() async {
    if(loading || busy || !foreground)return;
    final request=++generation;setState((){loading=true;error=null;clearImage();pendingReason=null;requestId=newMessageRequestId();});
    try{
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      final result=await widget.backend.downloadPhoto(widget.path).timeout(const Duration(seconds:6));
      if(!mounted || request!=generation || !foreground)return;
      if(widget.backend.userId!=owner || result.length>2097152 || result.isEmpty)throw StateError('Photo unavailable');
      setState((){bytes=result;digest=sha256.convert(result).toString();});
    }catch(_){if(mounted&&request==generation)setState(()=>error='Fotoğraf yüklenemedi. Profil değişmiş olabilir; geri dönüp listeyi yenileyebilirsin.');}
    finally{if(mounted&&request==generation)setState(()=>loading=false);}
  }
  Future<void> submit() async {
    if(busy || !foreground || (bytes==null&&pendingDigest==null) || reason.text.trim().length<5)return;
    pendingReason??=reason.text.trim();pendingDigest??=digest;final request=generation;
    setState((){busy=true;error=null;});
    try{
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      await widget.backend.reportPhoto(targetId:widget.targetId,path:widget.path,requestId:requestId,reason:pendingReason!,digest:pendingDigest!).timeout(const Duration(seconds:15));
      if(!mounted || request!=generation || !foreground)return;
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      Navigator.of(context).pop(true);
    }catch(_){if(mounted&&request==generation)setState(()=>error='Şikâyet doğrulanamadı. Aynı fotoğraf ve gerekçeyle tekrar deneyebilirsin. Fotoğraf değiştiyse geri dönüp profili yenile.');}
    finally{if(mounted&&request==generation)setState(()=>busy=false);}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    foreground=state==AppLifecycleState.resumed;
    generation++;
    setState((){clearImage();loading=false;busy=false;});
    // Preserve an uncertain request's identity/reason; do not silently report a new image.
    if(foreground && pendingReason==null)load();
    else if(foreground)setState(()=>error='Gönderimin sonucu doğrulanmadı. Önceden onayladığın fotoğraf ve gerekçeyle aynı isteği tekrar deneyebilirsin.');
  }
  @override
  void dispose(){generation++;clearImage();reason.dispose();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Fotoğrafı şikâyet et')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      if(loading)const LinearProgressIndicator(),
      if(bytes!=null)Image.memory(bytes!,height:220,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Text('Fotoğraf görüntülenemiyor.')),
      const Text('Bu fotoğrafın bir kopyası şikâyetle birlikte inceleme için saklanır. Profil fotoğrafının değiştirilmesi bu kaydı silmez.'),
      const SizedBox(height:12),
      TextField(controller:reason,readOnly:busy||pendingReason!=null,maxLength:1000,maxLines:3,
        onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Şikâyet gerekçesi (en az 5 karakter)')),
      if(error!=null)Text(error!),
      FilledButton(onPressed:busy||loading||(bytes==null&&pendingDigest==null)||reason.text.trim().length<5?null:submit,
        child:Text(busy?'Gönderiliyor…':pendingReason==null?'Fotoğrafla birlikte gönder':'Aynı şikâyeti tekrar dene')),
      if(bytes==null&&pendingReason==null)TextButton(onPressed:loading?null:load,child:const Text('Fotoğrafı tekrar yükle')),
    ])));
}
