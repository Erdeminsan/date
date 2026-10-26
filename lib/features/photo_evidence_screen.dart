import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../backend/repository.dart';

class PhotoEvidenceScreen extends StatefulWidget {
  const PhotoEvidenceScreen({super.key,required this.backend,required this.reportId});
  final Backend backend;
  final String reportId;
  @override
  State<PhotoEvidenceScreen> createState()=>_PhotoEvidenceScreenState();
}
class _PhotoEvidenceScreenState extends State<PhotoEvidenceScreen> with WidgetsBindingObserver {
  late final String owner;
  Timer? timer;
  Uint8List? bytes;
  bool busy=false,foreground=true,checking=false;
  int generation=0;
  String? error;
  @override
  void initState(){super.initState();owner=widget.backend.userId;WidgetsBinding.instance.addObserver(this);load();timer=Timer.periodic(const Duration(seconds:5),(_)=>check());}
  void clear(){if(bytes!=null)MemoryImage(bytes!).evict();bytes=null;}
  Future<void> check() async {
    if(checking||!foreground)return;checking=true;
    try{
      if(widget.backend.userId!=owner || !await widget.backend.moderationPhotoAccess(widget.reportId).timeout(const Duration(seconds:5)))throw StateError('Access lost');
      if(widget.backend.userId!=owner)throw StateError('Session changed');
    }catch(_){if(mounted&&foreground){generation++;setState((){clear();busy=false;error='Fotoğrafa erişilemiyor. Yetkini ve bağlantını kontrol et.';});}}
    finally{checking=false;}
  }
  Future<void> load() async {
    if(busy||!foreground)return;final request=++generation;
    setState((){clear();busy=true;error=null;});
    try{
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      final result=await widget.backend.moderationPhoto(widget.reportId).timeout(const Duration(seconds:8));
      if(!mounted||request!=generation||!foreground)return;
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      setState(()=>bytes=result);
    }catch(_){if(mounted&&request==generation)setState(()=>error='Fotoğraf kanıtı yüklenemedi.');}
    finally{if(mounted&&request==generation)setState(()=>busy=false);}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){foreground=state==AppLifecycleState.resumed;generation++;setState((){clear();busy=false;});if(foreground)load();}
  @override
  void dispose(){generation++;timer?.cancel();clear();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Fotoğraf kanıtı')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
    if(busy)const LinearProgressIndicator(),
    if(error!=null)Text(error!),
    if(bytes!=null)Image.memory(bytes!,height:MediaQuery.sizeOf(context).height*0.65,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Text('Kayıtlı görsel çözümlenemedi.')),
    TextButton(onPressed:busy?null:load,child:const Text('Yenile')),
  ])));
}
