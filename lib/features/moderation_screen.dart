import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import 'appeals_screen.dart';
import 'message_evidence_view.dart';
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key,required this.backend});
  final Backend backend;
  @override
  State<ModerationScreen> createState()=>_ModerationScreenState();
}
class _ModerationScreenState extends State<ModerationScreen> with WidgetsBindingObserver {
  late final String owner;
  Timer? timer;
  final rows=<ModerationReport>[];
  final sanctions=<ModerationSanction>[];
  FeedCursor? cursor;
  bool busy=false,foreground=true,checking=false,dialogOpen=false;
  int generation=0;
  String status='pending';
  String? error;
  @override
  void initState(){super.initState();owner=widget.backend.userId;WidgetsBinding.instance.addObserver(this);load();timer=Timer.periodic(const Duration(seconds:5),(_)=>checkAccess());}
  void clearAccess(){
    generation++;
    if(dialogOpen){dialogOpen=false;Navigator.of(context).pop();}
    setState((){rows.clear();sanctions.clear();cursor=null;busy=false;error='Şikâyetlere erişilemiyor. Yetkini ve bağlantını kontrol et.';});
  }
  Future<void> checkAccess() async {
    if(!foreground||checking)return;checking=true;
    try {
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      final allowed=await widget.backend.moderationAccess().timeout(const Duration(seconds:5));
      if(mounted&&foreground&&(!allowed||widget.backend.userId!=owner))clearAccess();
    }catch(_){if(mounted&&foreground)clearAccess();}
    finally{checking=false;}
  }
  Future<void> load({bool more=false}) async {
    if(busy||!foreground)return;
    final request=++generation;final before=more?cursor:null;
    setState((){busy=true;error=null;if(!more){rows.clear();sanctions.clear();cursor=null;}});
    try {
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      if(status=='sanctions'){
        final page=await widget.backend.moderationSanctions(before:before).timeout(const Duration(seconds:6));
        if(!mounted||request!=generation||!foreground)return;
        if(widget.backend.userId!=owner)throw StateError('Session changed');
        setState((){final merged={for(final r in [...sanctions,...page.items])r.id:r};sanctions..clear()..addAll(merged.values);cursor=page.next;});
      }else{
        final page=await widget.backend.moderationReports(status:status,before:before).timeout(const Duration(seconds:6));
        if(!mounted||request!=generation||!foreground)return;
        if(widget.backend.userId!=owner)throw StateError('Session changed');
        setState((){final merged={for(final r in [...rows,...page.items])r.id:r};rows..clear()..addAll(merged.values);cursor=page.next;});
      }
    }catch(_){if(mounted&&request==generation)clearAccess();}
    finally{if(mounted&&request==generation)setState(()=>busy=false);}
  }
  Future<void> review(ModerationReport report) async {
    var decision='dismissed',note='';dialogOpen=true;
    final accepted=await showDialog<bool>(useRootNavigator: false, context:context,builder:(context)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title:const Text('Şikâyet kararı'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButton<String>(isExpanded:true,value:decision,items:const [
          DropdownMenuItem(value:'dismissed',child:Text('İşlem gerekmiyor')),
          DropdownMenuItem(value:'escalated',child:Text('İleri inceleme gerekli')),
        ],onChanged:(v)=>update(()=>decision=v!)),
        TextField(maxLength:1000,maxLines:3,onChanged:(v)=>update(()=>note=v),decoration:const InputDecoration(labelText:'Gerekçe (en az 5 karakter)')),
        const Text('Bu karar hesap yaptırımı uygulamaz.'),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:note.trim().length<5?null:()=>Navigator.pop(context,true),child:const Text('Kararı kaydet'))],
    )));
    dialogOpen=false;
    if(accepted!=true||!mounted||!foreground||busy)return;
    final request=++generation;setState(()=>busy=true);
    try {
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      await widget.backend.reviewReport(report.id,decision,note.trim()).timeout(const Duration(seconds:6));
      if(!mounted||request!=generation)return;
      setState(()=>busy=false);await load();
    }catch(_){if(mounted&&request==generation){clearAccess();setState(()=>error='Karar doğrulanamadı. Listeyi yenileyerek durumu kontrol et; önceki karar değiştirilemez.');}}
  }
  Future<void> sanctionAction({ModerationReport? report,ModerationSanction? sanction}) async {
    var hours=24,reason='',publicNotice='';final lifting=sanction!=null;dialogOpen=true;
    final accepted=await showDialog<bool>(useRootNavigator: false, context:context,builder:(context)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title:Text(lifting?'Kısıtlamayı kaldır':'Hesabı süreli kısıtla'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(lifting?sanction.reportedName:report!.reportedName),
        if(!lifting)DropdownButton<int>(isExpanded:true,value:hours,items:const [
          DropdownMenuItem(value:24,child:Text('24 saat')),DropdownMenuItem(value:168,child:Text('7 gün')),
        ],onChanged:(v)=>update(()=>hours=v!)),
        Text(lifting?'Başka aktif kısıtlama varsa hesap kapalı kalır.':'Bu hesap keşif, eşleşme, sohbet ve oyun işlemlerine erişemeyecek.'),
        TextField(key:const ValueKey('internal-reason'),maxLength:1000,maxLines:3,onChanged:(v)=>update(()=>reason=v),decoration:const InputDecoration(labelText:'İç gerekçe (kullanıcıya gösterilmez)')),
        if(!lifting)...[
          const Text('Aşağıdaki açıklama kullanıcıya gösterilir. Şikâyetçi kimliğini ve özel inceleme notlarını paylaşma.'),
          TextField(key:const ValueKey('public-notice'),maxLength:1000,maxLines:3,onChanged:(v)=>update(()=>publicNotice=v),decoration:const InputDecoration(labelText:'Kullanıcıya açıklama (en az 5 karakter)')),
        ],
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:reason.trim().length<5||(!lifting&&publicNotice.trim().length<5)?null:()=>Navigator.pop(context,true),child:Text(lifting?'Kaldırmayı onayla':'Kısıtlamayı onayla'))],
    )));
    dialogOpen=false;
    if(accepted!=true||!mounted||!foreground||busy)return;
    final request=++generation;setState(()=>busy=true);
    try{
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      if(lifting){await widget.backend.liftAccountSanction(sanction.id,reason.trim()).timeout(const Duration(seconds:6));}
      else{await widget.backend.suspendReportedAccount(report!.id,hours,reason.trim(),publicNotice.trim()).timeout(const Duration(seconds:6));}
      if(!mounted||request!=generation||!foreground)return;
      setState((){busy=false;status='sanctions';});await load();
    }catch(_){if(mounted&&request==generation){clearAccess();setState(()=>error='İşlem doğrulanamadı. Kısıtlamalar listesini yenileyerek kontrol et; süre otomatik uzatılmaz.');}}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    foreground=state==AppLifecycleState.resumed;generation++;
    if(dialogOpen){dialogOpen=false;Navigator.of(context).pop();}
    setState((){rows.clear();sanctions.clear();cursor=null;busy=false;});if(foreground)load();
  }
  @override
  void dispose(){generation++;timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Şikâyet inceleme'),actions:[TextButton(onPressed:busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AppealsScreen(backend:widget.backend,moderator:true))),child:const Text('İtirazlar'))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      SegmentedButton<String>(segments:const [ButtonSegment(value:'pending',label:Text('Bekleyen')),ButtonSegment(value:'reviewed',label:Text('İncelenen')),ButtonSegment(value:'sanctions',label:Text('Kısıtlamalar'))],selected:{status},
        onSelectionChanged:busy?null:(values){setState(()=>status=values.first);load();}),
      if(busy)const LinearProgressIndicator(),
      if(error!=null)Text(error!),
      if(!busy&&error==null&&rows.isEmpty&&sanctions.isEmpty)Text(status=='sanctions'?'Kısıtlama kaydı yok.':'Bu listede şikâyet yok.'),
      for(final r in rows)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${r.reporterName} → ${r.reportedName}'),Text(r.reason),
        if(r.evidence!=null)MessageEvidenceView(evidence:r.evidence!),
        if(r.decision!=null)...[Text(r.decision=='dismissed'?'İşlem gerekmiyor':'İleri inceleme gerekli'),Text(r.note??''),if(r.decision=='escalated')TextButton(onPressed:busy?null:()=>sanctionAction(report:r),child:const Text('Süreli kısıtla'))]
        else TextButton(onPressed:busy?null:()=>review(r),child:const Text('İncele')),
      ]))),
      for(final s in sanctions)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(s.reportedName),Text('İç gerekçe: ${s.reason}'),Text('Kullanıcıya açıklama: ${s.publicNotice ?? 'Bu eski kayıt için ayrı açıklama bulunmuyor.'}'),Text(s.active?'Aktif kısıtlama':'Kısıtlama sona erdi'),
        Text('Bitiş: ${s.expiresAt.toLocal()}'),if(s.liftReason!=null)Text('Kaldırma gerekçesi: ${s.liftReason}'),
        if(s.active)TextButton(onPressed:busy?null:()=>sanctionAction(sanction:s),child:const Text('Kısıtlamayı kaldır')),
      ]))),
      if(cursor!=null)TextButton(onPressed:busy?null:()=>load(more:true),child:const Text('Daha fazla kayıt')),
      TextButton(onPressed:busy?null:()=>load(),child:const Text('Yenile')),
    ]));
}
