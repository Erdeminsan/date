import 'package:flutter/material.dart';
import '../backend/repository.dart';
class DiscoveryPreferencesScreen extends StatefulWidget {
  const DiscoveryPreferencesScreen({super.key,required this.backend});
  final Backend backend;
  @override
  State<DiscoveryPreferencesScreen> createState()=>_DiscoveryPreferencesScreenState();
}
class _DiscoveryPreferencesScreenState extends State<DiscoveryPreferencesScreen> {
  late final String owner;
  RangeValues ages=const RangeValues(18,100);
  bool loading=true,saving=false,loaded=false;
  String? error;
  @override
  void initState(){super.initState();owner=widget.backend.userId;load();}
  Future<void> load() async {
    setState((){loading=true;error=null;});
    try {
      if(widget.backend.userId!=owner) throw StateError('Session changed');
      final prefs=await widget.backend.discoveryPreferences().timeout(const Duration(seconds:6));
      if(!mounted)return;
      if(widget.backend.userId!=owner) throw StateError('Session changed');
      setState((){ages=RangeValues(prefs.minAge.toDouble(),(prefs.maxAge??100).toDouble());loaded=true;});
    }catch(_){if(mounted)setState(()=>error='Tercihler alınamadı. Tekrar dene.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> save() async {
    if(saving||!loaded)return;
    setState((){saving=true;error=null;});
    try {
      await widget.backend.saveDiscoveryPreferences(ages.start.round(),ages.end==100?null:ages.end.round(),expectedUserId:owner).timeout(const Duration(seconds:6));
      if(!mounted)return;
      if(widget.backend.userId!=owner)throw StateError('Session changed');
      Navigator.pop(context,true);
    }catch(_){if(mounted)setState(()=>error='Tercihler kaydedilemedi. Aynı seçimle tekrar deneyebilirsin.');}
    finally{if(mounted)setState(()=>saving=false);}
  }
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!saving,child:Scaffold(
    appBar:AppBar(title:const Text('Keşfet tercihleri')),
    body:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('Görmek istediğin yaş aralığı',style:TextStyle(fontSize:24)),
      const Text('Bu tercih yalnız senin keşfet listeni filtreler. Mevcut eşleşmelerini değiştirmez. Doğum tarihleri gösterilmez; yaş aralığına uygunluk sunucuda hesaplanır.'),
      if(loading) const LinearProgressIndicator()
      else if(loaded) ...[
        Text('${ages.start.round()} – ${ages.end==100?"100+":ages.end.round()} yaş'),
        RangeSlider(values:ages,min:18,max:100,divisions:82,
          labels:RangeLabels('${ages.start.round()}',ages.end==100?'100+':'${ages.end.round()}'),
          onChanged:saving?null:(v)=>setState(()=>ages=v)),
        TextButton(onPressed:saving?null:()=>setState(()=>ages=const RangeValues(18,100)),child:const Text('Tüm yetişkinler')),
        FilledButton(onPressed:saving?null:save,child:Text(saving?'Kaydediliyor…':'Kaydet')),
      ],
      if(error!=null)...[Text(error!),TextButton(onPressed:saving||loading?null:load,child:const Text('Yeniden yükle'))],
    ]),
  ));
}
