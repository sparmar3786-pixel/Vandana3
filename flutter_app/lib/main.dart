import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';

void main() => runApp(const AlgoApp());

class AlgoApp extends StatelessWidget {
  const AlgoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'NSE Algo Signal',
    theme: ThemeData.dark(useMaterial3: true),
    home: const Terminal(),
  );
}

class Terminal extends StatefulWidget {
  const Terminal({super.key});
  @override State<Terminal> createState() => _TerminalState();
}

class _TerminalState extends State<Terminal> {
  static const screens = <String>[
    'Dashboard','Market','Commodity','Signals','OI Lab','Watchlist','Search',
    'Charts','Option Chain','News','Market Details','Angel API','NSE',
    'NSE MCP','Data','Instruments','Settings','More','Strategies','AI Analysis','System Health'
  ];
  static const icons = <IconData>[
    Icons.dashboard, Icons.show_chart, Icons.precision_manufacturing,
    Icons.notifications_active, Icons.analytics, Icons.star, Icons.search,
    Icons.candlestick_chart, Icons.table_chart, Icons.article, Icons.info_outline,
    Icons.key, Icons.language, Icons.hub, Icons.storage, Icons.list_alt,
    Icons.tune, Icons.more_horiz, Icons.schema, Icons.psychology, Icons.health_and_safety
  ];
  int selected = 0;
  String backendUrl = 'https://nse-algo-backend-live-production.up.railway.app';
  String apiToken = 'change-me';
  String connection = 'Connecting...';
  bool angelConnected = false;
  String nseMcpStatus = 'Not checked';
  String angelLoginStatus = '';
  String csvStatus = '';
  Map<String,dynamic>? signal;
  List<dynamic> liveMarket = <dynamic>[];
  List<dynamic> liveCandles = <dynamic>[];
  List<dynamic> liveOptionRows = <dynamic>[];
  List<dynamic> liveOIBuild = <dynamic>[];
  String selectedChartToken = '99926000';
  String selectedChartExchange = 'NSE';
  String selectedInterval = 'FIVE_MINUTE';
  static const intervalMap = <String,String>{'1m':'ONE_MINUTE','2m':'TWO_MINUTE','3m':'THREE_MINUTE','5m':'FIVE_MINUTE','10m':'TEN_MINUTE','15m':'FIFTEEN_MINUTE','30m':'THIRTY_MINUTE','1H':'ONE_HOUR','1D':'ONE_DAY'};
  bool angelDataBusy = false;
  bool lightMode = false;
  String marketFilter = 'Indices';
  List<dynamic> strategyRegistry = <dynamic>[];
  List<dynamic> strategyEvidence = <dynamic>[];
  bool strategyBusy = false;
  bool aiBusy = false;
  bool terminalBusy = false;
  bool aiCrossVerified = false;
  String aiReason = '';
  String aiLastRun = '';
  String aiFinal = 'WAIT';
  String aiError = '';
  Map<String,dynamic> diagnostics = <String,dynamic>{};
  Map<String,dynamic> latestAudit = <String,dynamic>{};
  bool diagnosticsBusy = false;
  List<dynamic> aiProviders = <dynamic>[
    {'id':'gpt56-luna','name':'GPT-5.6 Luna','model':'gpt-5.6-luna','configured':false,'status':'Server key required'},
    {'id':'claude-sonnet','name':'Claude Sonnet 4.6','model':'claude-sonnet-4-6','configured':false,'status':'Server key required'},
    {'id':'gpt56-sol','name':'GPT-5.6 Sol','model':'gpt-5.6-sol','configured':false,'status':'Server key required'},
    {'id':'deepseek','name':'DeepSeek Chat','model':'deepseek-chat','configured':false,'status':'Server key required'},
    {'id':'gemini-flash','name':'Gemini 2.5 Flash','model':'gemini-2.5-flash','configured':false,'status':'Server key required'},
    {'id':'grok-4','name':'Grok 4','model':'grok-4','configured':false,'status':'Server key required'},
  ];
  String optionFilter = 'NIFTY';
  String selectedComponentIndex = 'NIFTY';
  List<dynamic> indexComponents = <dynamic>[];
  bool componentBusy = false;
  String chartTool = 'None';
  Offset? chartPointA;
  Offset? chartPointB;
  String selectedChartSymbol = 'NIFTY';
  String commodityQuery = '';
  final Set<String> selectedIndicators = <String>{};
  Map<String,dynamic>? terminalData;
  Timer? timer;

  @override void initState() {
    super.initState();
    fetchTerminal();
    fetchStrategies();
    fetchAIStatus();
    fetchDiagnostics();
    fetchIndexComponents('NIFTY');
    timer = Timer.periodic(const Duration(seconds: 5), (_) => fetchTerminal());
  }
  @override void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> fetchTerminal() async {
    if (terminalBusy) return;
    terminalBusy = true;
    try {
      final response = await http.get(
        Uri.parse(backendUrl + '/v1/terminal'),
        headers: <String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:5));
      if (!mounted) return;
      dynamic decoded;
      try { decoded=jsonDecode(response.body); } catch (_) { decoded=null; }
      final conn=decoded is Map<String,dynamic>?decoded['connection']:null;
      final angel=conn is Map && conn['angel']==true;
      setState(() {
        terminalData=decoded is Map<String,dynamic>?decoded:null;
        final s=terminalData?['signals'];
        final m=terminalData?['nse_mcp'];
        signal=s is Map<String,dynamic>?s:null;
        connection=response.statusCode==200 && conn is Map && conn['server']==true && conn['angel']==true
          ? 'Connected'
          : response.statusCode==200 && conn is Map && conn['server']==true
            ? 'Backend connected / Angel not connected'
            : 'HTTP '+response.statusCode.toString();
        nseMcpStatus=m is Map && m['connected']==true?'Connected':'Not connected';
      });
      if (angel && mounted) await fetchAngelMarket();
    } catch (_) {
      if (mounted) setState(() => connection='Backend not connected');
    } finally {
      terminalBusy=false;
    }
  }

  Future<void> downloadNseCsv() async {
    setState(() => csvStatus = 'Fetching NSE option chain...');
    try {
      final response = await http.get(
        Uri.parse(backendUrl + '/v1/nse/option-chain.csv?symbol=' + optionFilter),
        headers: <String,String>{'x-token': apiToken},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        setState(() => csvStatus = 'NSE CSV unavailable: HTTP ' + response.statusCode.toString());
        return;
      }
      await FileSaver.instance.saveFile(
        name: optionFilter + '_NSE_option_chain',
        bytes: response.bodyBytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) setState(() => csvStatus = 'NIFTY NSE option-chain CSV saved.');
    } catch (e) {
      if (mounted) setState(() => csvStatus = 'CSV download failed. ' + e.toString());
    }
  }

  @override Widget build(BuildContext context) => Theme(
    data: lightMode ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true),
    child: PopScope<Object?>(
    canPop: selected == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && selected != 0 && mounted) setState(() => selected = 0);
    },
    child: Scaffold(
    appBar: AppBar(
      leading: selected == 0 ? null : IconButton(onPressed: () => setState(() => selected = 0), icon: const Icon(Icons.arrow_back)),
      title: Text(screens[selected]),
      actions: <Widget>[
        IconButton(onPressed: fetchTerminal, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: () => setState(() => lightMode = !lightMode), icon: Icon(lightMode ? Icons.dark_mode : Icons.light_mode), tooltip: lightMode ? 'Dark mode' : 'Light mode'),
        IconButton(onPressed: openSettings, icon: const Icon(Icons.settings)),
      ],
    ),
    drawer: Drawer(
      child: SafeArea(child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const DrawerHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Icon(Icons.candlestick_chart, size: 42),
            SizedBox(height: 10),
            Text('NSE Algo Signal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('18-screen live market terminal'),
          ])),
          for (int i=0; i<screens.length; i++) ListTile(
            leading: Icon(icons[i]),
            title: Text(screens[i]),
            selected: selected == i,
            onTap: () { Navigator.pop(context); setState(() => selected = i); },
          ),
        ],
      )),
    ),
    body: buildScreen(),
  )));

  Widget buildScreen() {
    if (selected == 0) return dashboard();
    if (selected == 1) return marketPage();
    if (selected == 2) return commodityPage();
    if (selected == 3) return signals();
    if (selected == 4) return oiLabPage();
    if (selected == 5) return watchlistPage();
    if (selected == 6) return searchPage();
    if (selected == 7) return chartsPage();
    if (selected == 8) return optionChain();
    if (selected == 9) return newsPage();
    if (selected == 10) return marketDetailsPage();
    if (selected == 11) return angelApi();
    if (selected == 13) return nseMcp();
    if (selected == 16) return settingsPage();
    if (selected == 17) return morePage();
    if (selected == 18) return strategiesPage();
    if (selected == 19) return aiAnalysisPage();
    if (selected == 20) return systemHealthPage();
    return dataPage(screens[selected]);
  }

  Widget dashboard() {
    final action = signal?['action']?.toString() ?? 'WAIT';
    return ListView(padding: const EdgeInsets.fromLTRB(12,10,12,20), children: <Widget>[
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: <Widget>[
        const CircleAvatar(radius:22,child:Icon(Icons.candlestick_chart)),
        const SizedBox(width:10),
        const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('NSE Algo Signal',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
          Text('Fast market workspace • 18 screens',style:TextStyle(fontSize:12)),
        ])),
        Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),color:connection=='Connected'?Colors.green.withOpacity(.16):Colors.orange.withOpacity(.16)),child:Text(connection,style:TextStyle(fontSize:11,color:connection=='Connected'?Colors.green:Colors.orange,fontWeight:FontWeight.w600))),
      ]))),
      const SizedBox(height:10),
      Wrap(spacing:8,runSpacing:8,children:[
        _metricTile('Connection',connection,Icons.link),
        _metricTile('Indices',liveMarket.isEmpty?'—':liveMarket.length.toString(),Icons.show_chart),
        _metricTile('Candles',liveCandles.isEmpty?'—':liveCandles.length.toString(),Icons.candlestick_chart),
        _metricTile('Option rows',liveOptionRows.isEmpty?'—':liveOptionRows.length.toString(),Icons.table_chart),
      ]),
      const SizedBox(height:10),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.bolt,size:18),const SizedBox(width:7),const Text('CURRENT SIGNAL',style:TextStyle(fontWeight:FontWeight.bold)),const Spacer(),const SizedBox.shrink()]),
        const SizedBox(height:4),Text(action.replaceAll('_',' '),style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),
        if(signal!=null) ...[row('Symbol',signal!['symbol']),row('Spot',signal!['spot']),row('LTP',signal!['ltp'])] else const Text('No live signal payload received.',style:TextStyle(fontSize:12)),
      ]))),
      const SizedBox(height:10),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('QUICK ACCESS',style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Wrap(spacing:7,runSpacing:7,children:[
          ActionChip(label:const Text('Indian Indices'),avatar:const Icon(Icons.show_chart,size:16),onPressed:()=>setState(()=>selected=1)),
          ActionChip(label:const Text('Option Chain'),avatar:const Icon(Icons.table_chart,size:16),onPressed:(){setState(()=>selected=8);fetchOptionRows();}),
          ActionChip(label:const Text('Charts'),avatar:const Icon(Icons.candlestick_chart,size:16),onPressed:()=>setState(()=>selected=7)),
          ActionChip(label:const Text('Strategies'),avatar:const Icon(Icons.schema,size:16),onPressed:()=>setState(()=>selected=18)),
          ActionChip(label:const Text('NSE MCP'),avatar:const Icon(Icons.hub,size:16),onPressed:()=>setState(()=>selected=13)),
        ]),
      ]))),
      const SizedBox(height:10),
      Card(child:ListTile(
        leading:Icon((terminalData?['connection'] is Map && terminalData!['connection']['nse'] == true) ? Icons.check_circle : Icons.warning_amber_rounded,
          color:(terminalData?['connection'] is Map && terminalData!['connection']['nse'] == true) ? Colors.green : Colors.orange),
        title:const Text('NSE SIGNAL FEED'),
        subtitle:Text(signal?['action']?.toString().replaceAll('_',' ') ?? 'WAIT • awaiting engine payload'),
        trailing:IconButton(onPressed:fetchTerminal,icon:const Icon(Icons.refresh)),
      )),
      const SizedBox(height:10),
      infoCard('Data policy','Real API/data only. No fabricated market values. Strategy engine remains evidence-gated.',Colors.blue),
    ]);
  }

  Widget _metricTile(String title,String value,IconData icon)=>SizedBox(width:MediaQuery.of(context).size.width>520?180:(MediaQuery.of(context).size.width-40)/2,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(icon,size:20),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:11)),const SizedBox(height:3),Text(value,style:const TextStyle(fontSize:14,fontWeight:FontWeight.bold),overflow:TextOverflow.ellipsis)]))]))));



  Future<void> fetchAngelMarket() async {
    try {
      final r=await http.get(Uri.parse(backendUrl+'/v1/angel/market'),headers:<String,String>{'x-token':apiToken}).timeout(const Duration(seconds:8));
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        final rows=d is Map && d['data'] is Map ? (d['data']['fetched'] ?? <dynamic>[]) : <dynamic>[];
        if(mounted) setState(()=>liveMarket=rows is List ? rows : <dynamic>[]);
      }
    } catch (_) {}
  }

  Future<void> openNamedIndex(String name) async {
    String norm(String x)=>x.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
    final target=norm(name);
    dynamic hit;
    bool matches(String s){
      if(name=='NIFTY 50') return s=='NIFTY'||s=='NIFTY50';
      if(name=='BANK NIFTY') return s=='BANKNIFTY'||s=='NIFTYBANK';
      if(name=='FINNIFTY') return s=='FINNIFTY'||s=='NIFTYFINSERVICE';
      if(name=='MIDCAP SELECT') return s=='MIDCPNIFTY'||s=='NIFTYMIDCAPSELECT'||s=='MIDCAPSELECT';
      if(name=='SENSEX') return s=='SENSEX'||s=='BSESENSEX';
      if(name=='BANKEX') return s=='BANKEX'||s=='BSEBANKEX';
      return s==target;
    }
    for(final q in liveMarket){
      final s=norm((q['tradingSymbol']??q['tradingsymbol']??q['symbol']??q['indexName']??'').toString());
      if(matches(s)){ hit=q; break; }
    }
    if(hit!=null){ await openQuoteChart(hit); return; }
    await fetchAngelMarket();
    for(final q in liveMarket){
      final s=norm((q['tradingSymbol']??q['tradingsymbol']??q['symbol']??q['indexName']??'').toString());
      if(matches(s)){ await openQuoteChart(q); return; }
    }
  }

  Future<void> openQuoteChart(dynamic q) async {
    final token=(q['symbolToken']??q['symboltoken']??q['token']??'').toString();
    if(token.isEmpty)return;
    selectedChartToken=token;
    selectedChartExchange=(q['exchange']??'NSE').toString();
    final n=(q['indexName']??q['tradingSymbol']??q['tradingsymbol']??'NIFTY').toString().toUpperCase();
    if(n.contains('BANK')) selectedChartSymbol='BANKNIFTY';
    else if(n.contains('FIN')) selectedChartSymbol='FINNIFTY';
    else if(n.contains('MID')) selectedChartSymbol='MIDCPNIFTY';
    else if(n.contains('SENSEX')) selectedChartSymbol='SENSEX';
    else if(n.contains('BANKEX')) selectedChartSymbol='BANKEX';
    else selectedChartSymbol='NIFTY';
    chartPointA=null; chartPointB=null; chartTool='None';
    setState(()=>selected=7);
    await fetchCandles();
  }

  Future<void> searchAndOpenCommodity(String query) async {
    try {
      final r=await http.get(Uri.parse(backendUrl+'/v1/angel/search?exchange=MCX&q='+Uri.encodeQueryComponent(query)),headers:<String,String>{'x-token':apiToken}).timeout(const Duration(seconds:10));
      if(r.statusCode==200&&mounted){
        final d=jsonDecode(r.body);
        setState(()=>terminalData={'commoditySearch':d});
        final rows=d is Map&&d['data'] is List?d['data']:<dynamic>[];
        if(rows.isNotEmpty) await openSearchResult(rows.first,'MCX');
      }
    } catch (_) {}
  }

  Future<void> openSearchResult(dynamic x,String exchange) async {
    final token=(x['symboltoken']??x['symbolToken']??x['token']??'').toString();
    if(token.isEmpty)return;
    selectedChartToken=token; selectedChartExchange=exchange;
    setState(()=>selected=7);
    await fetchCandles();
  }

  Future<void> fetchCandles() async {
    setState(()=>angelDataBusy=true);
    try {
      final u=backendUrl+'/v1/angel/candles?exchange='+selectedChartExchange+'&token='+selectedChartToken+'&interval='+selectedInterval+'&days=1';
      final r=await http.get(Uri.parse(u),headers:<String,String>{'x-token':apiToken}).timeout(const Duration(seconds:12));
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        final rows=d is Map && d['data'] is List ? d['data'] : <dynamic>[];
        if(mounted) setState(()=>liveCandles=rows is List ? rows : <dynamic>[]);
      }
    } catch (_) {} finally { if(mounted) setState(()=>angelDataBusy=false); }
  }

  Future<void> fetchOptionRows() async {
    setState(()=>angelDataBusy=true);
    try {
      final r=await http.get(
        Uri.parse(backendUrl+'/v1/option-chain?symbol='+Uri.encodeQueryComponent(optionFilter)+'&count=10'),
        headers:<String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:20));
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        final rows=d is Map && d['rows'] is List ? d['rows'] : <dynamic>[];
        if(mounted) setState(()=>liveOptionRows=rows is List ? rows : <dynamic>[]);
      } else if(mounted) {
        setState(()=>liveOptionRows=<dynamic>[]);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Option chain HTTP '+r.statusCode.toString())));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Option chain unavailable: '+e.toString())));
    } finally { if(mounted) setState(()=>angelDataBusy=false); }
  }

  Future<void> fetchIndexComponents([String? index]) async {
    final key=(index??selectedComponentIndex).toUpperCase();
    if(key=='SENSEX'||key=='BANKEX') {
      if(mounted) setState(()=>indexComponents=<dynamic>[]);
      return;
    }
    if(mounted) setState(()=>componentBusy=true);
    try {
      final r=await http.get(
        Uri.parse(backendUrl+'/v1/index-components?index='+Uri.encodeQueryComponent(key)),
        headers:<String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:15));
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        final rows=d is Map && d['rows'] is List ? d['rows'] : <dynamic>[];
        if(mounted) setState(()=>indexComponents=rows is List ? rows : <dynamic>[]);
      } else if(mounted) {
        setState(()=>indexComponents=<dynamic>[]);
      }
    } catch (_) {
      if(mounted) setState(()=>indexComponents=<dynamic>[]);
    } finally {
      if(mounted) setState(()=>componentBusy=false);
    }
  }

  Future<void> fetchOIBuild() async {
    setState(()=>angelDataBusy=true);
    try {
      final r=await http.get(Uri.parse(backendUrl+'/v1/angel/oi-buildup?datatype=Long%20Built%20Up&expirytype=NEAR'),headers:<String,String>{'x-token':apiToken}).timeout(const Duration(seconds:12));
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        final rows=d is Map && d['data'] is List ? d['data'] : <dynamic>[];
        if(mounted) setState(()=>liveOIBuild=rows is List ? rows : <dynamic>[]);
      }
    } catch (_) {} finally { if(mounted) setState(()=>angelDataBusy=false); }
  }

  Widget indexCard(dynamic q) {
    final name=(q['tradingSymbol']??q['tradingsymbol']??'-').toString();
    return Card(child:ListTile(
      title:Text(name,style:const TextStyle(fontWeight:FontWeight.bold)),
      subtitle:Text('Open '+(q['open']??'-').toString()+'  High '+(q['high']??'-').toString()+'  Low '+(q['low']??'-').toString()),
      trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:<Widget>[
        Text((q['ltp']??'-').toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        Text((q['netChange']??'').toString()+' '+(q['percentChange']??'').toString())
      ]),
    ));
  }

  Widget marketPage() => ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:<Widget>[
    const Text('Market',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:4),const Text('INDICES • NSE / BSE • tap any index to open its chart.',style:TextStyle(fontSize:12)),
    const SizedBox(height:10),
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      for(final f in const ['Indices','NSE','BSE']) Padding(
        padding:const EdgeInsets.only(right:6),
        child:ChoiceChip(label:Text(f),selected:marketFilter==f,onSelected:(_)=>setState(()=>marketFilter=f)),
      ),
    ])),
    const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('TRADING INDICES',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      Wrap(spacing:6,runSpacing:6,children:[
        for(final x in const ['NIFTY 50','BANK NIFTY','FINNIFTY','MIDCAP SELECT','SENSEX','BANKEX'])
          ActionChip(label:Text(x),onPressed:()=>openNamedIndex(x)),
      ]),
    ]))),
    const SizedBox(height:10),
    ...liveMarket.where((q){
      final ex=(q['exchange']??q['exchangeType']??'').toString().toUpperCase();
      return marketFilter=='Indices' || ex==marketFilter;
    }).map((q)=>Card(child:ListTile(
      leading:const Icon(Icons.show_chart),
      title:Text((q['tradingSymbol']??q['tradingsymbol']??q['symbol']??q['indexName']??'-').toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
      subtitle:Text('LTP '+(q['ltp']??'—').toString()+' • '+(q['exchange']??'').toString()),
      trailing:Text((q['percentChange']??q['netChange']??'—').toString()),
      onTap:()=>openQuoteChart(q),
    ))),
    if(liveMarket.isEmpty) infoCard('Live indices','Connect Angel One to load current index prices and chart tokens.',Colors.orange),
    FilledButton.icon(onPressed:fetchAngelMarket,icon:const Icon(Icons.refresh),label:const Text('REFRESH INDICES')),
  ]);
  Widget commodityPage() => ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:<Widget>[
    const Text('Commodity',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:4),const Text('MCX instruments are kept separate from Indian indices.',style:TextStyle(fontSize:12)),
    const SizedBox(height:10),
    TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search commodity',hintText:'CRUDEOIL, GOLD, SILVER, NATURALGAS',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>commodityQuery=v)),
    const SizedBox(height:8),
    Wrap(spacing:6,runSpacing:6,children:[
      for(final x in const ['CRUDEOIL','CRUDEOILM','GOLD','SILVER','NATURALGAS'])if(commodityQuery.isEmpty||x.contains(commodityQuery.toUpperCase()))ActionChip(label:Text(x),onPressed:()=>searchAndOpenCommodity(x)),
    ]),
    const SizedBox(height:8),
    infoCard('Auto-select','Select a commodity above → Angel search resolves the contract → chart opens for the selected instrument.',Colors.blue),
    if(terminalData?['commoditySearch'] is Map) ...((terminalData!['commoditySearch']['data'] is List ? terminalData!['commoditySearch']['data'] : <dynamic>[]).map((x)=>Card(child:ListTile(title:Text((x['tradingsymbol']??'-').toString()),subtitle:Text('MCX • '+(x['symboltoken']??'-').toString()),onTap:()=>openSearchResult(x,'MCX'))))),
  ]);

  Widget oiLabPage() => ListView(padding:const EdgeInsets.all(16),children:<Widget>[
    const Text('OI Lab',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    infoCard('Live source','Angel One SmartAPI OI Buildup',Colors.blue),
    ...liveOIBuild.map((x)=>Card(child:ListTile(
      title:Text((x['tradingSymbol']??'-').toString()),
      subtitle:Text('LTP '+(x['ltp']??'-').toString()+' • OI '+(x['opnInterest']??'-').toString()),
      trailing:Text((x['netChangeOpnInterest']??'-').toString()),
    ))),
    if(liveOIBuild.isEmpty) infoCard('OI buildup','Press refresh to fetch Long Built Up from Angel One.',Colors.orange),
    FilledButton.icon(onPressed:fetchOIBuild,icon:const Icon(Icons.refresh),label:const Text('REFRESH OI BUILDUP')),
  ]);

  Widget watchlistPage() => ListView(padding:const EdgeInsets.all(16),children:<Widget>[
    const Text('Watchlist',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    infoCard('Live source','Angel One SmartAPI',Colors.blue),
    ...liveMarket.map((q)=>ListTile(title:Text((q['tradingSymbol']??'-').toString()),trailing:Text((q['ltp']??'-').toString()))),
    if(liveMarket.isEmpty) infoCard('Watchlist','Connect Angel One to populate live instruments.',Colors.orange),
  ]);

  Widget searchPage() => ListView(padding:const EdgeInsets.all(16),children:<Widget>[
    const Text('Search',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    const Text('Search Scrip • Angel One SmartAPI'),
    const SizedBox(height:10),
    TextField(
      decoration:const InputDecoration(labelText:'NSE / BSE / MCX symbol',border:OutlineInputBorder()),
      onSubmitted:(q) async {
        if(q.trim().isEmpty)return;
        try{
          final r=await http.get(Uri.parse(backendUrl+'/v1/angel/search?exchange=NSE&q='+Uri.encodeQueryComponent(q.trim())),headers:<String,String>{'x-token':apiToken});
          if(r.statusCode==200 && mounted) setState(()=>terminalData={'search':jsonDecode(r.body)});
        }catch(_){}
      },
    ),
    const SizedBox(height:12),
    if(terminalData?['search'] is Map)
      ...((terminalData!['search']['data'] is List ? terminalData!['search']['data'] : <dynamic>[]).map((x)=>Card(child:ListTile(title:Text((x['tradingsymbol']??'-').toString()),subtitle:Text((x['exchange']??'').toString()+' • Token '+(x['symboltoken']??'-').toString()))))),
  ]);

  Widget chartsPage() => ListView(padding:const EdgeInsets.fromLTRB(8,8,8,20),children:<Widget>[
    Row(children:[
      const Expanded(child:Text('Charts',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))),
      IconButton(onPressed:fetchCandles,icon:const Icon(Icons.refresh)),
    ]),
    const SizedBox(height:6),
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      for(final x in const ['None','Horizontal','Vertical','Fib Retracement','Long Position','Short Position'])
        Padding(padding:const EdgeInsets.only(right:5),child:ChoiceChip(
          label:Text(x),selected:chartTool==x,onSelected:(_){setState(()=>chartTool=x);},
        )),
    ])),
    const SizedBox(height:6),
    Row(children:[
      Expanded(child:FilledButton.icon(onPressed:()=>showModalBottomSheet<void>(context:context,builder:(_)=>_selectionSheet('TIME',const ['1m','2m','3m','5m','10m','15m','30m','1H','1D'],(x){setState(()=>selectedInterval=intervalMap[x]!);fetchCandles();})),icon:const Icon(Icons.schedule),label:Text('TIME • '+(intervalMap.entries.firstWhere((e)=>e.value==selectedInterval,orElse:()=>const MapEntry('5m','FIVE_MINUTE')).key)))),
      const SizedBox(width:6),
      Expanded(child:FilledButton.icon(onPressed:()=>showModalBottomSheet<void>(context:context,builder:(_)=>_selectionSheet('INDICATORS',const ['EMA 8','EMA 13','SMA 20','SMA 50','VWAP','RSI 14','MACD','Bollinger','Volume','ATR 14'],(x){setState(()=>selectedIndicators.contains(x)?selectedIndicators.remove(x):selectedIndicators.add(x));})),icon:const Icon(Icons.tune),label:Text('INDICATORS • '+selectedIndicators.length.toString()))),
    ]),
    const SizedBox(height:6),
    Row(children:[
      Expanded(child:OutlinedButton.icon(onPressed:(){setState((){selected=8;optionFilter=selectedChartSymbol;chartTool='None';});fetchOptionRows();},icon:const Icon(Icons.table_chart),label:Text('OPTION '+selectedChartSymbol))),
      const SizedBox(width:6),
      Expanded(child:OutlinedButton.icon(onPressed:()=>setState((){chartPointA=null;chartPointB=null;chartTool='None';}),icon:const Icon(Icons.clear),label:const Text('CLEAR DRAWING'))),
    ]),
    const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(5),child:SizedBox(
      height:460,
      child: liveCandles.isEmpty
        ? Center(child:Text(angelDataBusy?'Loading live candles...':'Select an index or commodity to load its chart.'))
        : GestureDetector(
            behavior:HitTestBehavior.opaque,
            onTapDown:(d){
              if(chartTool=='Horizontal'||chartTool=='Vertical'){
                setState(()=>chartPointA=d.localPosition);
              }
            },
            onPanStart:(d){
              if(chartTool!='None'&&chartTool!='Horizontal'&&chartTool!='Vertical') {
                setState(()=>chartPointA=d.localPosition);
              }
            },
            onPanUpdate:(d){
              if(chartTool!='None'&&chartTool!='Horizontal'&&chartTool!='Vertical') {
                setState(()=>chartPointB=d.localPosition);
              }
            },
            onPanEnd:(_){
              if(chartTool=='Horizontal'||chartTool=='Vertical') return;
            },
            child:CustomPaint(
              painter:CandlePainter(liveCandles,Set<String>.from(selectedIndicators),tool:chartTool,pointA:chartPointA,pointB:chartPointB),
              size:Size.infinite,
            ),
          ),
    ))),
    const SizedBox(height:8),
    infoCard('Chart source',selectedChartExchange+' • token '+selectedChartToken+' • tool '+chartTool,Colors.blue),
  ]);
  Widget _selectionSheet(String title,List<String> items,void Function(String) onTap){
    return SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:10),
      Wrap(spacing:6,runSpacing:6,children:[for(final x in items)FilterChip(label:Text(x),selected:title=='TIME'?selectedInterval==intervalMap[x]:selectedIndicators.contains(x),onSelected:(_){onTap(x);Navigator.pop(context);})]),
      const SizedBox(height:8),
    ])));
  }

  Widget optionChain() => ListView(padding:const EdgeInsets.fromLTRB(8,8,8,20),children:<Widget>[
    Row(children:[
      const Expanded(child:Text('Option Chain',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))),
      IconButton(onPressed:fetchOptionRows,icon:const Icon(Icons.refresh)),
      IconButton(onPressed:downloadNseCsv,icon:const Icon(Icons.download),tooltip:'Download NSE CSV'),
    ]),
    const SizedBox(height:6),
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      for(final x in const ['NIFTY','BANKNIFTY','FINNIFTY','MIDCPNIFTY','SENSEX','BANKEX'])
        Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(x),selected:optionFilter==x,onSelected:(_){setState(()=>optionFilter=x);fetchOptionRows();})),
    ])),
    const SizedBox(height:8),
    if(csvStatus.isNotEmpty) Text(csvStatus,style:const TextStyle(fontSize:11)),
    if(liveOptionRows.isEmpty) infoCard('Live option chain','Live chain uses Angel One first and falls back to NSE data for supported NSE indices. LTP/OI remain source-backed; no fabricated rows.',Colors.orange),
    if(liveOptionRows.isNotEmpty) _optionTable(),
  ]);

  Widget _optionTable(){
    final grouped=<dynamic,Map<String,dynamic>>{};
    for(final r in liveOptionRows){
      final s=r['strike'];
      grouped.putIfAbsent(s,()=> <String,dynamic>{});
      grouped[s]![r['type'].toString()]=r;
    }
    final strikes=grouped.keys.toList()..sort((a,b)=>(a as num).compareTo(b as num));
    return Card(child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(
      columns:const [
        DataColumn(label:Text('CALL LTP')),DataColumn(label:Text('CALL OI')),
        DataColumn(label:Text('STRIKE')),DataColumn(label:Text('PUT OI')),DataColumn(label:Text('PUT LTP')),
      ],
      rows:[for(final s in strikes) DataRow(cells:[
        DataCell(Text(_v(grouped[s]?['CE'],'ltp'))),
        DataCell(_oiCell(grouped[s]?['CE'])),
        DataCell(Text(s.toString(),style:const TextStyle(fontWeight:FontWeight.bold))),
        DataCell(_oiCell(grouped[s]?['PE'])),
        DataCell(Text(_v(grouped[s]?['PE'],'ltp'))),
      ])],
    )));
  }

  String _v(dynamic r,String k)=>r is Map?(r[k]??'—').toString():'—';
  Widget _oiCell(dynamic r){
    final v=r is Map?r['oi']:null;
    final n=v is num?v.toDouble():double.tryParse(v?.toString()??'');
    final d=r is Map?r['oiChange']:null;
    final positive=d is num&&d>0, negative=d is num&&d<0;
    return Text((positive?'+':negative?'-':'')+(n?.toStringAsFixed(0)??'—'),style:TextStyle(color:positive?Colors.green:negative?Colors.red:null,fontWeight:FontWeight.w600));
  }


  Widget newsPage() => ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:<Widget>[
    Row(children:[const Expanded(child:Text('News',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))),IconButton(onPressed:fetchTerminal,icon:const Icon(Icons.refresh))]),
    const Text('Live/verified news feed • source and timestamp shown with each item.',style:TextStyle(fontSize:12)),
    const SizedBox(height:10),
    Row(children:[Expanded(child:ChoiceChip(label:const Text('Market'),selected:true,onSelected:(_){ })),const SizedBox(width:8),const Text('Latest first')]),
    const SizedBox(height:8),
    infoCard('News feed','No fabricated headlines. Live cards will appear when the verified server-side news adapter supplies them.',Colors.orange),
    Card(child:ListTile(leading:const Icon(Icons.article_outlined),title:const Text('Live news area'),subtitle:const Text('Headline • source • time • related index/stock'),trailing:const Icon(Icons.chevron_right))),
    Card(child:ListTile(leading:const Icon(Icons.notifications_none),title:const Text('Market alerts'),subtitle:const Text('News-driven alerts will be displayed here when available.'),trailing:const Icon(Icons.chevron_right))),
  ]);

  double _componentChange(dynamic x){
    if(x is! Map) return 0;
    final v=x['pChange']??x['percentChange']??x['change'];
    return v is num ? v.toDouble() : double.tryParse(v?.toString()??'0')??0;
  }

  Widget _componentSection(String title,List<dynamic> rows,Color color){
    if(rows.isEmpty) return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text(title+' • none'));
    final sorted=[...rows]..sort((a,b)=>_componentChange(b).compareTo(_componentChange(a)));
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:TextStyle(fontWeight:FontWeight.bold,color:color)),
      const SizedBox(height:4),
      for(final x in sorted.take(30)) ListTile(
        dense:true,
        leading:Icon(Icons.circle,size:9,color:color),
        title:Text((x['symbol']??x['name']??'-').toString()),
        subtitle:Text((x['name']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis),
        trailing:Text((_componentChange(x)>=0?'+':'')+_componentChange(x).toStringAsFixed(2)+'%',
          style:TextStyle(color:color,fontWeight:FontWeight.bold)),
      ),
    ]);
  }

  Widget marketDetailsPage() => ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:<Widget>[
    const Text('Market Details',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      for(final x in const ['NIFTY','BANK NIFTY','SENSEX'])
        Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(x),selected:selectedComponentIndex==x,onSelected:(_){
          setState(()=>selectedComponentIndex=x);
          fetchIndexComponents(x);
          openNamedIndex(x=='NIFTY'?'NIFTY 50':x);
        })),
    ])),
    const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('NEWS',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      const Text('Verified/server-side market news appears here when the news adapter supplies source + timestamp.'),
      const SizedBox(height:8),
      ListTile(leading:const Icon(Icons.article_outlined),title:const Text('Live news feed'),subtitle:const Text('No fabricated headlines.')),
    ]))),
    const SizedBox(height:8),
    Row(children:[
      Expanded(child:_breadthBox('GREEN',indexComponents.where((x)=>_componentChange(x)>0).length.toString()+' stocks',Colors.green)),
      const SizedBox(width:8),
      Expanded(child:_breadthBox('RED',indexComponents.where((x)=>_componentChange(x)<0).length.toString()+' stocks',Colors.red)),
    ]),
    const SizedBox(height:8),
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Expanded(child:Text(selectedComponentIndex+' COMPONENTS',style:const TextStyle(fontWeight:FontWeight.bold))),
        if(componentBusy) const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)),
        IconButton(onPressed:()=>fetchIndexComponents(),icon:const Icon(Icons.refresh)),
      ]),
      const SizedBox(height:6),
      if(indexComponents.isEmpty && !componentBusy)
        Text((selectedComponentIndex=='SENSEX')?'SENSEX constituents feed is not available from the NSE endpoint.':'No constituent data returned. Connect Angel/NSE and refresh.',style:const TextStyle(fontSize:11)),
      if(indexComponents.isNotEmpty) ...[
        _componentSection('GREEN • GAINERS',indexComponents.where((x)=>_componentChange(x)>0).toList(),Colors.green),
        const Divider(),
        _componentSection('RED • LOSERS',indexComponents.where((x)=>_componentChange(x)<0).toList(),Colors.red),
      ],
    ]))),
    const SizedBox(height:8),
    infoCard('Index constituents','Live NSE constituent prices and percentage change are shown separately from the index chart.',Colors.blue),
    infoCard('Index selection','Tap NIFTY, BANK NIFTY or SENSEX above. The selected instrument is sent to the chart.',Colors.blue),
  ]);


  Widget angelApi() => AngelApiForm(
    backendUrl: backendUrl,
    apiToken: apiToken,
    connection: connection,
    status: angelLoginStatus,
    onConnected: fetchTerminal,
    onStatus: (v) => setState(() => angelLoginStatus = v),
  );

  Widget settingsPage() => ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:<Widget>[
    const Text('Settings',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    Card(child:SwitchListTile(title:const Text('Light mode'),subtitle:const Text('Switch between dark and light workspace'),value:lightMode,onChanged:(v)=>setState(()=>lightMode=v))),
    infoCard('Backend URL',backendUrl,Colors.blue),
    const SizedBox(height:8),
    Card(child:ListTile(leading:const Icon(Icons.schedule),title:const Text('TIME'),subtitle:const Text('Select chart timeframe'),onTap:()=>showModalBottomSheet<void>(context:context,builder:(_)=>_selectionSheet('TIME',const ['1m','2m','3m','5m','10m','15m','30m','1H','1D'],(x){setState(()=>selectedInterval=intervalMap[x]!);fetchCandles();})))),
    Card(child:ListTile(leading:const Icon(Icons.tune),title:const Text('INDICATORS'),subtitle:const Text('Select chart indicators'),onTap:()=>showModalBottomSheet<void>(context:context,builder:(_)=>_selectionSheet('INDICATORS',const ['EMA 8','EMA 13','SMA 20','SMA 50','VWAP','RSI 14','MACD','Bollinger','Volume','ATR 14'],(x){setState(()=>selectedIndicators.contains(x)?selectedIndicators.remove(x):selectedIndicators.add(x));})))),
    FilledButton.icon(onPressed:openSettings,icon:const Icon(Icons.dns),label:const Text('EDIT SERVER CONNECTION')),
  ]);


  Future<void> fetchStrategies() async {
    if (strategyBusy) return;
    setState(() => strategyBusy = true);
    try {
      final r = await http.get(Uri.parse(backendUrl + '/v1/strategies'),
        headers: <String,String>{'x-token': apiToken}).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        if (d is Map) {
          final reg = d['registry']; final ev = d['evidence'];
          if (mounted) setState(() {
            strategyRegistry = reg is List ? reg : <dynamic>[];
            strategyEvidence = ev is List ? ev : <dynamic>[];
          });
        }
      }
    } catch (_) {} finally { if (mounted) setState(() => strategyBusy = false); }
  }

  Widget signals() {
    final action = signal?['action']?.toString() ?? 'WAIT';
    final reason = signal?['reason']?.toString() ?? 'Live signal payload pending.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(12,10,12,20),
      children: [
        const Text('Signals', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Engine-backed signal terminal. No signal is forced when evidence is insufficient.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CURRENT ENGINE STATE', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(action.replaceAll('_', ' '), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(reason),
              const SizedBox(height: 10),
              if (signal != null) ...[
                row('Symbol', signal!['symbol']),
                row('Spot', signal!['spot']),
                row('LTP', signal!['ltp']),
                row('Strike', signal!['strike']),
                row('Entry', signal!['entry']),
                row('Stop Loss', signal!['sl']),
                row('Target', signal!['target']),
              ] else
                const Text('Connect Angel One and wait for the live engine payload.'),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: fetchTerminal,
          icon: const Icon(Icons.refresh),
          label: const Text('REFRESH SIGNAL'),
        ),
        const SizedBox(height: 8),
        infoCard('Signal policy', 'CALL BUY / PUT BUY only when the engine has qualifying evidence; otherwise WAIT or NO QUALIFYING TRADE.', Colors.blue),
      ],
    );
  }

  Widget nseMcp() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12,10,12,20),
      children: [
        const Text('NSE MCP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Official NSE Streamable HTTP MCP data bridge.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(nseMcpStatus == 'Connected' ? Icons.check_circle : Icons.cloud_off,
              color: nseMcpStatus == 'Connected' ? Colors.green : Colors.orange),
            title: const Text('NSE MCP STATUS'),
            subtitle: Text(nseMcpStatus),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: downloadNseCsv,
          icon: const Icon(Icons.download),
          label: const Text('DOWNLOAD NSE OPTION-CHAIN CSV'),
        ),
        if (csvStatus.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(csvStatus),
        ),
        const SizedBox(height: 8),
        infoCard('Data rule', 'The app displays only data returned by the configured NSE/Angel backend. Missing data stays unavailable.', Colors.blue),
      ],
    );
  }

  Widget strategiesPage() {
    final active = strategyEvidence.where((x) => x is Map && x['state'] == 'active').length;
    final unavailable = strategyEvidence.where((x) => x is Map && x['state'] == 'unavailable').length;
    final grouped = <String,List<dynamic>>{};
    for (final x in strategyRegistry) {
      if (x is Map) grouped.putIfAbsent((x['family'] ?? 'Other').toString(), () => <dynamic>[]).add(x);
    }
    return RefreshIndicator(
      onRefresh: fetchStrategies,
      child: ListView(padding: const EdgeInsets.fromLTRB(12,10,12,20), children: [
        const Text('Strategy Master', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Complete registered strategy catalogue. Only evidence-backed modules may become active.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _metricTile('Registered', strategyRegistry.length.toString(), Icons.schema)),
          const SizedBox(width: 8),
          Expanded(child: _metricTile('Active', active.toString(), Icons.bolt)),
          const SizedBox(width: 8),
          Expanded(child: _metricTile('Unavailable', unavailable.toString(), Icons.block)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: strategyBusy ? null : fetchStrategies, icon: const Icon(Icons.sync), label: Text(strategyBusy ? 'LOADING...' : 'REFRESH STRATEGIES')),
        const SizedBox(height: 8),
        for (final entry in grouped.entries) Card(
          child: ExpansionTile(
            title: Text(entry.key),
            subtitle: Text('${entry.value.length} modules'),
            children: [
              for (final x in entry.value) ListTile(
                dense: true,
                leading: const Icon(Icons.checklist, size: 18),
                title: Text('${x['id']}. ${x['name']}'),
                trailing: _strategyStateIcon(x['id']),
              )
            ],
          ),
        ),
      ]),
    );
  }

  Widget _strategyStateIcon(dynamic id) {
    final hit = strategyEvidence.where((x) => x is Map && x['id'] == id).cast<dynamic>().toList();
    if (hit.isEmpty) return const Icon(Icons.help_outline, size: 18);
    final state = hit.first['state'];
    if (state == 'active') return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    if (state == 'unavailable') return const Icon(Icons.block, color: Colors.orange, size: 18);
    return const Icon(Icons.remove_circle_outline, size: 18);
  }

  Future<void> fetchDiagnostics() async {
    if (diagnosticsBusy) return;
    if (mounted) setState(() => diagnosticsBusy = true);
    try {
      final r = await http.get(
        Uri.parse(backendUrl + '/v1/diagnostics'),
        headers: <String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:8));
      if (r.statusCode == 200 && mounted) {
        final d = jsonDecode(r.body);
        if (d is Map<String,dynamic>) setState(() => diagnostics = d);
      }
      final a = await http.get(
        Uri.parse(backendUrl + '/v1/audit/latest'),
        headers: <String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:8));
      if (a.statusCode == 200 && mounted) {
        final d = jsonDecode(a.body);
        if (d is Map<String,dynamic>) setState(() => latestAudit = d);
      }
    } catch (_) {
      if (mounted && diagnostics.isEmpty) {
        setState(() => diagnostics = <String,dynamic>{'ok':false});
      }
    } finally {
      if (mounted) setState(() => diagnosticsBusy = false);
    }
  }

  Widget _healthTile(String title, String value, bool good) => Card(
    child: ListTile(
      leading: Icon(good ? Icons.check_circle : Icons.warning_amber_rounded,
        color: good ? Colors.green : Colors.orange),
      title: Text(title),
      subtitle: Text(value),
    ),
  );

  Future<void> fetchAIStatus() async {
    try {
      final r=await http.get(
        Uri.parse(backendUrl+'/v1/ai/status'),
        headers:<String,String>{'x-token':apiToken},
      ).timeout(const Duration(seconds:8));
      if(!mounted) return;
      if(r.statusCode==200){
        dynamic d;
        try { d=jsonDecode(r.body); } catch (_) { d=null; }
        if(d is Map && d['providers'] is List){
          final incoming=(d['providers'] as List).whereType<Map>().toList();
          final byId=<String,Map<String,dynamic>>{
            for(final p in incoming) p['id'].toString():Map<String,dynamic>.from(p)
          };
          final merged=aiProviders.map((old){
            final id=(old is Map?old['id']:'').toString();
            return byId[id] ?? old;
          }).toList();
          for(final p in incoming){
            final id=(p['id']??'').toString();
            if(id.isNotEmpty && !merged.any((x)=>x is Map && x['id']==id)) merged.add(p);
          }
          setState(() { aiProviders=merged; aiError=''; });
        }
      } else {
        setState(() => aiError='AI status HTTP '+r.statusCode.toString()+'. Provider cards remain available.');
      }
    } catch(e) {
      if(mounted) setState(() => aiError='AI status unavailable: '+e.toString());
    }
  }

  Future<void> runAIValidation() async {
    if(aiBusy || !mounted) return;
    setState(() {
      aiBusy=true;
      aiError='';
      aiReason='Preparing fresh terminal data...';
      aiCrossVerified=false;
    });
    try {
      await fetchTerminal();
      final payload=<String,dynamic>{
        'terminal':terminalData ?? <String,dynamic>{},
        'signal':signal ?? <String,dynamic>{},
        'strategy_count':strategyRegistry.length,
        'strategy_evidence':strategyEvidence.take(120).toList(),
        'timestamp':DateTime.now().toIso8601String(),
      };
      if(mounted) setState(() => aiReason=terminalData==null && signal==null
        ? 'Live terminal data is unavailable. The server will attempt its own current snapshot.'
        : 'Submitting current market snapshot to all configured AI providers...');
      final r=await http.post(
        Uri.parse(backendUrl+'/v1/ai/validate'),
        headers:<String,String>{'x-token':apiToken,'Content-Type':'application/json'},
        body:jsonEncode({'payload':payload}),
      ).timeout(const Duration(seconds:35));
      if(!mounted) return;
      dynamic d;
      try { d=jsonDecode(r.body); } catch (_) { d=null; }
      if(r.statusCode==200 && d is Map){
        final incoming=d['providers'] is List ? d['providers'] as List : <dynamic>[];
        setState((){
          aiFinal=(d['final']??'WAIT').toString();
          aiCrossVerified=d['cross_verified']==true;
          aiReason=(d['reason']??'').toString();
          aiLastRun=DateTime.now().toLocal().toString().substring(0,19);
          if(incoming.isNotEmpty){
            final byId=<String,Map<String,dynamic>>{
              for(final p in incoming.whereType<Map>()) p['id'].toString():Map<String,dynamic>.from(p)
            };
            aiProviders=aiProviders.map((old){
              final id=(old is Map?old['id']:'').toString();
              return byId[id] ?? old;
            }).toList();
          }
        });
      } else {
        setState(()=>aiError='AI validation HTTP '+r.statusCode.toString()+(d is Map && d['error']!=null ? ': '+d['error'].toString() : ''));
      }
    } catch(e) {
      if(mounted) setState(()=>aiError='AI validation failed safely: '+e.toString());
    } finally {
      if(mounted) setState(() => aiBusy=false);
    }
  }

  List<Widget> _aiProviderCards() {
    final out=<Widget>[];
    for(var i=0;i<aiProviders.length;i++){
      final raw=aiProviders[i];
      if(raw is Map) out.add(_aiProviderCard(i,raw));
    }
    return out;
  }

  Widget _aiProviderCard(int index, dynamic raw) {
    final p=Map<String,dynamic>.from(raw as Map);
    final ok=p['status']=='ok' || p['configured']==true;
    final name=(p['name']??'AI Provider').toString();
    final status=(p['status']??(p['configured']==true?'Ready':'Server key required')).toString();
    final model=(p['model']??'').toString();
    final body=(p['text']??p['error']??'Not run yet.').toString();
    return Card(child:ExpansionTile(
      leading:CircleAvatar(child:Icon(ok?Icons.check:Icons.key_off,size:18)),
      title:Text((index+1).toString()+' • '+name,style:const TextStyle(fontWeight:FontWeight.bold)),
      subtitle:Text(status),
      trailing:Text(model,style:const TextStyle(fontSize:9)),
      children:[
        Padding(
          padding:const EdgeInsets.fromLTRB(16,0,16,14),
          child:Align(alignment:Alignment.centerLeft,child:Text(body,style:const TextStyle(fontSize:11,height:1.35))),
        ),
      ],
    ));
  }

  Widget aiAnalysisPage() {
    final configured=aiProviders.where((x)=>x is Map && x['configured']==true).length;
    final c=terminalData?['connection'];
    final terminalConnected=c is Map && c['angel']==true;
    return RefreshIndicator(
      onRefresh:fetchAIStatus,
      child:ListView(
        padding:const EdgeInsets.fromLTRB(12,10,12,24),
        children:[
          Row(children:[
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('AI Analysis',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
              SizedBox(height:3),
              Text('6-AI server validation • no double-tap required • keys stay on backend',style:TextStyle(fontSize:11)),
            ])),
            IconButton(onPressed:fetchAIStatus,icon:const Icon(Icons.refresh)),
          ]),
          const SizedBox(height:10),
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('LIVE INPUT',style:TextStyle(fontWeight:FontWeight.bold,letterSpacing:.7)),
            const SizedBox(height:7),
            Row(children:[
              Icon(terminalConnected?Icons.cloud_done:Icons.cloud_off,size:18,color:terminalConnected?Colors.green:Colors.orange),
              const SizedBox(width:7),
              Expanded(child:Text(terminalConnected
                ? 'Fresh Angel/terminal snapshot is available for AI validation.'
                : 'Live terminal snapshot is not confirmed; server-side snapshot fallback remains enabled.')),
            ]),
            const SizedBox(height:5),
            Text('Configured providers: $configured / 6',style:const TextStyle(fontSize:11)),
          ]))),
          const SizedBox(height:10),
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('FINAL VALIDATION',style:TextStyle(fontWeight:FontWeight.bold,letterSpacing:.7)),
            const SizedBox(height:8),
            Row(children:[
              Container(width:12,height:12,decoration:BoxDecoration(shape:BoxShape.circle,color:aiFinal=='CALL BUY'?Colors.green:aiFinal=='PUT BUY'?Colors.red:Colors.orange)),
              const SizedBox(width:8),
              Expanded(child:Text(aiFinal,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800))),
              Icon(aiCrossVerified?Icons.verified:Icons.pending_outlined,color:aiCrossVerified?Colors.green:Colors.orange),
            ]),
            if(aiReason.isNotEmpty) Padding(padding:const EdgeInsets.only(top:6),child:Text(aiReason,style:const TextStyle(fontSize:11))),
            if(aiLastRun.isNotEmpty) Padding(padding:const EdgeInsets.only(top:3),child:Text('Last run: $aiLastRun',style:const TextStyle(fontSize:10))),
            const SizedBox(height:10),
            SizedBox(width:double.infinity,child:FilledButton.icon(
              onPressed:aiBusy?null:runAIValidation,
              icon:aiBusy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_awesome),
              label:Text(aiBusy?'RUNNING 6-AI VALIDATION...':'RUN 6-AI VALIDATION'),
            )),
            if(aiError.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),child:Text(aiError,style:const TextStyle(color:Colors.red,fontSize:11))),
          ]))),
          const SizedBox(height:10),
          Column(children:_aiProviderCards()),
          const SizedBox(height:6),
          infoCard(
            configured==0?'AI server keys required':'AI server ready',
            configured==0
              ? 'Set provider API keys on the Render backend. The APK never stores them.'
              : 'Tap RUN 6-AI VALIDATION. No market-card double-tap or hidden activation step is required.',
            configured==0?Colors.orange:Colors.green,
          ),
          const SizedBox(height:6),
          infoCard('Crash protection','Network calls are timeout-guarded, terminal polling is single-flight, malformed JSON is handled safely, and AI failures show an error instead of crashing the APK.',Colors.blue),
          const SizedBox(height:6),
          infoCard('Evidence rule','AI validates supplied market data only. Missing OI/volume/Greeks stays marked missing; no fabricated trade result or guaranteed win rate.',Colors.blue),
        ],
      ),
    );
  }

  Widget systemHealthPage() {
    final feeds = diagnostics['feeds'] is Map ? diagnostics['feeds'] as Map : <dynamic,dynamic>{};
    final strategies = diagnostics['strategies'] is Map ? diagnostics['strategies'] as Map : <dynamic,dynamic>{};
    final ai = diagnostics['ai'] is Map ? diagnostics['ai'] as Map : <dynamic,dynamic>{};
    final angel = feeds['angel'] is Map ? feeds['angel'] as Map : <dynamic,dynamic>{};
    final nse = feeds['nse'] is Map ? feeds['nse'] as Map : <dynamic,dynamic>{};
    final mcp = feeds['nse_mcp'] is Map ? feeds['nse_mcp'] as Map : <dynamic,dynamic>{};
    final freshness = angel['freshness'] is Map ? angel['freshness'] as Map : <dynamic,dynamic>{};
    final signalAction = (latestAudit['action'] ?? 'WAIT').toString();
    final reasons = latestAudit['reasons'] is List ? latestAudit['reasons'] as List : <dynamic>[];
    final activeEvidence = latestAudit['active_evidence'] is List ? latestAudit['active_evidence'] as List : <dynamic>[];
    return RefreshIndicator(
      onRefresh: fetchDiagnostics,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12,10,12,24),
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children: [
              Text('System Health', style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
              SizedBox(height:3),
              Text('Read-only engine, feed and validation diagnostics', style:TextStyle(fontSize:11)),
            ])),
            IconButton(onPressed:fetchDiagnostics, icon:const Icon(Icons.refresh)),
          ]),
          const SizedBox(height:10),
          _healthTile('Angel One',
            'Status: '+(angel['connected'] == true ? 'Connected' : 'Not connected')+
            ' • data age '+(freshness['age_sec'] ?? '—').toString()+' sec',
            angel['connected'] == true && freshness['state'] != 'expired'),
          _healthTile('NSE / MCP',
            mcp['connected'] == true ? 'Connected' : 'Unavailable',
            mcp['connected'] == true),
          _healthTile('NSE data',
            nse['connected'] == true ? 'No current error' : 'Data error',
            nse['connected'] == true),
          _healthTile('AI validation',
            (ai['configured'] ?? 0).toString()+' / '+(ai['total'] ?? 0).toString()+' providers configured',
            (ai['configured'] ?? 0) > 0),
          const SizedBox(height:8),
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('STRATEGY ENGINE',style:TextStyle(fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              row('Registered',strategies['registered']),
              row('Evaluated',strategies['evaluated']),
              row('Active evidence',strategies['active']),
              row('Unavailable',strategies['unavailable']),
              row('Not evaluated',strategies['not_evaluated']),
            ],
          ))),
          const SizedBox(height:8),
          Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('LATEST SIGNAL AUDIT',style:TextStyle(fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              Text(signalAction,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
              const SizedBox(height:5),
              if(reasons.isEmpty) const Text('No evidence recorded yet.',style:TextStyle(fontSize:11)),
              for(final x in reasons.take(10)) Padding(
                padding:const EdgeInsets.symmetric(vertical:2),
                child:Text('• '+x.toString(),style:const TextStyle(fontSize:11)),
              ),
              const SizedBox(height:6),
              Text('Active evidence: '+activeEvidence.length.toString(),style:const TextStyle(fontSize:11)),
            ],
          ))),
          const SizedBox(height:8),
          FilledButton.icon(
            onPressed:diagnosticsBusy?null:fetchDiagnostics,
            icon:diagnosticsBusy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.health_and_safety),
            label:Text(diagnosticsBusy?'CHECKING...':'RUN HEALTH CHECK'),
          ),
          const SizedBox(height:6),
          infoCard('Safety rule','Diagnostics are read-only. Missing or stale data does not create a signal.',Colors.blue),
        ],
      ),
    );
  }

  Widget morePage() => ListView(padding: const EdgeInsets.all(16), children: <Widget>[
    const Text('More', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    infoCard('Order mode','No order placement. Live market workspace.',Colors.orange),
    infoCard('Security','Keep Angel credentials server-side and never commit secrets.',Colors.blue),
    Card(child:ListTile(leading:const Icon(Icons.health_and_safety),title:const Text('System Health & Audit'),subtitle:const Text('Feed freshness • strategy evaluation • latest signal evidence'),trailing:const Icon(Icons.chevron_right),onTap:()=>setState(()=>selected=20))),
    infoCard('Navigation',screens.join(', '),Colors.blue),
  ]);

  Widget dataPage(String title) {
    if(title=='Data') return ListView(padding:const EdgeInsets.fromLTRB(12,10,12,20),children:[
      const Text('Data',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
      const SizedBox(height:4),const Text('Live OI, breadth and market payload workspace.',style:TextStyle(fontSize:12)),
      const SizedBox(height:10),
      Card(child:ListTile(leading:const Icon(Icons.bar_chart),title:const Text('NIFTY OI'),subtitle:const Text('Total / change / buildup — live payload pending'),trailing:const Text('—'))),
      Card(child:ListTile(leading:const Icon(Icons.bar_chart),title:const Text('BANK NIFTY OI'),subtitle:const Text('Total / change / buildup — live payload pending'),trailing:const Text('—'))),
      Card(child:ListTile(leading:const Icon(Icons.compare_arrows),title:const Text('OI Change'),subtitle:const Text('Increased / decreased contracts'),trailing:const Text('—'))),
      Card(child:ListTile(leading:const Icon(Icons.hub),title:const Text('NSE MCP Data'),subtitle:Text(nseMcpStatus),trailing:const Icon(Icons.chevron_right))),
      infoCard('Live data policy','No OI or market value is fabricated. The design is ready for the corresponding backend payload.',Colors.blue),
    ]);
    if(title=='Instruments') return ListView(padding:const EdgeInsets.all(16),children:[const Text('Instruments',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:8),infoCard('Instrument universe','NSE / BSE / NFO / MCX searchable instruments will be displayed here.',Colors.blue),const ListTile(leading:Icon(Icons.search),title:Text('Search instrument'),subtitle:Text('Symbol • exchange • token • segment'))]);
    return ListView(padding:const EdgeInsets.all(16),children:[Text(title,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:10),infoCard('Live data status',connection=='Connected'?'Backend connected.':'Backend not connected.',connection=='Connected'?Colors.green:Colors.orange),infoCard('Data source','Corresponding API/data adapter is handled by the backend.',Colors.blue)]);
  }

  Future<void> openSettings() async {
    final u = TextEditingController(text: backendUrl);
    final k = TextEditingController(text: apiToken);
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Server Settings'),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(controller:u, decoration: const InputDecoration(labelText:'Backend URL')),
        TextField(controller:k, obscureText:true, decoration: const InputDecoration(labelText:'API token')),
      ]),
      actions: <Widget>[TextButton(onPressed: () {
        setState(() { backendUrl = u.text.trim().replaceAll(RegExp(r'/$'), ''); apiToken = k.text.trim(); });
        Navigator.pop(d); fetchTerminal();
      }, child: const Text('Save'))],
    ));
    u.dispose(); k.dispose();
  }

  Widget _breadthBox(String title,String value,Color color)=>Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),border:Border.all(color:color.withOpacity(.35))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(fontSize:10,color:color,fontWeight:FontWeight.bold)),const SizedBox(height:5),Text(value,style:const TextStyle(fontSize:11))]));

  Widget infoCard(String title,String value,Color color) => Card(child: ListTile(
    leading: Icon(Icons.circle,color:color,size:13), title: Text(title), subtitle: Text(value),
  ));


  Widget row(String label,dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical:4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
      Text(label), Flexible(child:Text((value ?? '-').toString(), textAlign:TextAlign.right)),
    ]),
  );
}



class CandlePainter extends CustomPainter {
  final List<dynamic> rows;
  final Set<String> indicators;
  final String tool;
  final Offset? pointA;
  final Offset? pointB;
  CandlePainter(this.rows,this.indicators,{this.tool='None',this.pointA,this.pointB});

  List<double?> ema(List<double> v,int n){
    final out=List<double?>.filled(v.length,null); if(v.isEmpty)return out;
    double prev=v.first; out[0]=prev; final k=2/(n+1);
    for(int i=1;i<v.length;i++){prev=v[i]*k+prev*(1-k);out[i]=prev;} return out;
  }
  List<double?> rsi(List<double> v,int n){
    final out=List<double?>.filled(v.length,null); if(v.length<=n)return out;
    double gain=0,loss=0;
    for(int i=1;i<=n;i++){final d=v[i]-v[i-1];gain+=math.max(d,0);loss+=math.max(-d,0);}
    for(int i=n;i<v.length;i++){
      if(i>n){final d=v[i]-v[i-1];gain=(gain*(n-1)+math.max(d,0))/n;loss=(loss*(n-1)+math.max(-d,0))/n;}
      out[i]=loss==0?100:100-(100/(1+gain/loss));
    }
    return out;
  }

  @override void paint(Canvas canvas,Size size){
    final vals=rows.where((r)=>r is List&&r.length>=5).toList();
    if(vals.isEmpty)return;
    final close=vals.map<double>((r)=>(r[4]as num).toDouble()).toList();
    final overlays=<List<double?>>[];
    if(indicators.contains('EMA 8'))overlays.add(ema(close,8));
    if(indicators.contains('EMA 13'))overlays.add(ema(close,13));
    if(indicators.contains('SMA 20')){
      final a=List<double?>.filled(close.length,null);
      for(int i=19;i<close.length;i++)a[i]=close.sublist(i-19,i+1).reduce((x,y)=>x+y)/20;
      overlays.add(a);
    }
    if(indicators.contains('VWAP')){
      final a=List<double?>.filled(close.length,null);double pv=0,vol=0;
      for(int i=0;i<vals.length;i++){final r=vals[i];final h=(r[2]as num).toDouble(),l=(r[3]as num).toDouble(),cl=close[i];final v=r.length>5&&r[5] is num?(r[5]as num).toDouble():0;pv+=((h+l+cl)/3)*v;vol+=v;a[i]=vol>0?pv/vol:cl;} overlays.add(a);
    }
    double minV=double.infinity,maxV=-double.infinity;
    for(final r in vals){minV=math.min(minV,(r[3]as num).toDouble());maxV=math.max(maxV,(r[2]as num).toDouble());}
    for(final a in overlays)for(final x in a)if(x!=null){minV=math.min(minV,x);maxV=math.max(maxV,x);}
    final hasRsi=indicators.contains('RSI 14');
    final chartH=hasRsi?size.height*.75:size.height;
    final range=math.max(maxV-minV,.01),width=size.width/vals.length;
    double y(double v)=>chartH-(v-minV)/range*chartH;
    final grid=Paint()..color=Colors.white10..strokeWidth=.6;
    for(int i=0;i<5;i++){final yy=chartH*i/4;canvas.drawLine(Offset(0,yy),Offset(size.width,yy),grid);}
    final wick=Paint()..strokeWidth=1.2,body=Paint()..strokeWidth=math.max(2,width*.55);
    for(int i=0;i<vals.length;i++){
      final r=vals[i];final o=(r[1]as num).toDouble(),h=(r[2]as num).toDouble(),l=(r[3]as num).toDouble(),cl=close[i];final x=i*width+width/2,up=cl>=o;
      wick.color=up?Colors.green:Colors.red;body.color=wick.color;
      canvas.drawLine(Offset(x,y(h)),Offset(x,y(l)),wick);canvas.drawLine(Offset(x,y(o)),Offset(x,y(cl)),body);
    }
    final colors=[Colors.cyan,Colors.amber,Colors.purple,Colors.orange];
    for(int k=0;k<overlays.length;k++){final p=Paint()..color=colors[k%colors.length]..strokeWidth=1.5;final a=overlays[k];for(int i=1;i<a.length;i++)if(a[i-1]!=null&&a[i]!=null)canvas.drawLine(Offset((i-1)*width+width/2,y(a[i-1]!)),Offset(i*width+width/2,y(a[i]!)),p);}
    if(tool!='None' && pointA!=null){
      final draw=Paint()..strokeWidth=1.5..style=PaintingStyle.stroke;
      if(tool=='Horizontal'){
        draw.color=Colors.amber;
        canvas.drawLine(Offset(0,pointA!.dy),Offset(size.width,pointA!.dy),draw);
      } else if(tool=='Vertical'){
        draw.color=Colors.cyan;
        canvas.drawLine(Offset(pointA!.dx,0),Offset(pointA!.dx,chartH),draw);
      } else if(pointB!=null){
        final a=pointA!, b=pointB!;
        final left=math.min(a.dx,b.dx), right=math.max(a.dx,b.dx);
        final top=math.min(a.dy,b.dy), bottom=math.max(a.dy,b.dy);
        if(tool=='Fib Retracement'){
          draw.color=Colors.purple;
          final levels=<double>[0,.236,.382,.5,.618,.786,1];
          for(final lv in levels){
            final yy=a.dy+(b.dy-a.dy)*lv;
            canvas.drawLine(Offset(left,yy),Offset(right,yy),draw);
            final tp=TextPainter(text:TextSpan(text:(lv*100).toStringAsFixed(1)+'%',style:const TextStyle(fontSize:9,color:Colors.purple)),textDirection:TextDirection.ltr)..layout();
            tp.paint(canvas,Offset(left+3,yy-11));
          }
        } else if(tool=='Long Position'){
          draw.color=Colors.green;
          canvas.drawRect(Rect.fromLTRB(left,top,right,bottom),draw);
          canvas.drawLine(Offset(left,top),Offset(right,top),draw);
          canvas.drawLine(Offset(left,bottom),Offset(right,bottom),draw);
          final mid=(top+bottom)/2;
          canvas.drawLine(Offset(left,mid),Offset(right,mid),draw);
        } else if(tool=='Short Position'){
          draw.color=Colors.red;
          canvas.drawRect(Rect.fromLTRB(left,top,right,bottom),draw);
          canvas.drawLine(Offset(left,top),Offset(right,top),draw);
          canvas.drawLine(Offset(left,bottom),Offset(right,bottom),draw);
          final mid=(top+bottom)/2;
          canvas.drawLine(Offset(left,mid),Offset(right,mid),draw);
        }
      }
    }
    if(hasRsi){
      final rv=rsi(close,14),top=chartH+4,panelH=size.height-top-4,paint=Paint()..color=Colors.orange..strokeWidth=1.3;
      for(int i=1;i<rv.length;i++)if(rv[i-1]!=null&&rv[i]!=null){double ry(double z)=>top+panelH-(z/100)*panelH;canvas.drawLine(Offset((i-1)*width+width/2,ry(rv[i-1]!)),Offset(i*width+width/2,ry(rv[i]!)),paint);}
      final tp=TextPainter(text:const TextSpan(text:'RSI 14',style:TextStyle(fontSize:10,color:Colors.grey)),textDirection:TextDirection.ltr)..layout();tp.paint(canvas,Offset(4,top));
    }
  }
  @override bool shouldRepaint(covariant CandlePainter old)=>old.rows!=rows||old.indicators!=indicators||old.tool!=tool||old.pointA!=pointA||old.pointB!=pointB;
}

class AngelApiForm extends StatefulWidget {
  final String backendUrl;
  final String apiToken;
  final String connection;
  final String status;
  final VoidCallback onConnected;
  final ValueChanged<String> onStatus;

  const AngelApiForm({
    super.key,
    required this.backendUrl,
    required this.apiToken,
    required this.connection,
    required this.status,
    required this.onConnected,
    required this.onStatus,
  });

  @override
  State<AngelApiForm> createState() => _AngelApiFormState();
}

class _AngelApiFormState extends State<AngelApiForm> {
  final clientId = TextEditingController();
  final mpin = TextEditingController();
  final totp = TextEditingController();
  final apiKey = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    clientId.dispose();
    mpin.dispose();
    totp.dispose();
    apiKey.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final c = clientId.text.trim();
    final p = mpin.text.trim();
    final t = totp.text.trim();
    final k = apiKey.text.trim();

    if (c.isEmpty || p.isEmpty || k.isEmpty || !RegExp(r'^\d{6}$').hasMatch(t)) {
      widget.onStatus('Client ID, MPIN, API key and current 6-digit TOTP are required.');
      return;
    }

    setState(() => busy = true);
    widget.onStatus('Connecting to Angel One SmartAPI securely through Vandana2 backend...');

    try {
      final response = await http.post(
        Uri.parse(widget.backendUrl + '/v1/angel/login'),
        headers: <String,String>{
          'Content-Type': 'application/json',
          'x-token': widget.apiToken,
        },
        body: jsonEncode(<String,String>{
          'clientId': c,
          'pin': p,
          'totp': t,
          'apiKey': k,
        }),
      ).timeout(const Duration(seconds: 25));

      dynamic decoded;
      try { decoded = jsonDecode(response.body); } catch (_) { decoded = null; }

      if (response.statusCode == 200 &&
          decoded is Map &&
          decoded['connected'] == true) {
        widget.onStatus('CONNECTED • Angel One SmartAPI');
        widget.onConnected();
      } else {
        final detail = decoded is Map ? decoded['detail']?.toString() : null;
        widget.onStatus(detail == null || detail.isEmpty
            ? 'Login failed. Check Client ID, MPIN, TOTP, API key and backend.'
            : detail);
      }
    } catch (e) {
      widget.onStatus('Backend connection failed: ' + e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration field(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Angel API', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Secure SmartAPI connection'),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Text('LIVE DATA ONLY'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const <Widget>[
                  Text('BROKER CONNECTION', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('API'),
                ],
              ),
              const Divider(height: 24),
              TextField(
                controller: clientId,
                autocorrect: false,
                decoration: field('CLIENT ID', 'Enter Angel One Client ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mpin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: field('MPIN', 'Enter 4-digit MPIN'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: totp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: field('CURRENT TOTP', 'Enter current 6-digit TOTP'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKey,
                obscureText: true,
                autocorrect: false,
                decoration: field('SMARTAPI API KEY', 'Enter SmartAPI API key'),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: const <Widget>[
                    Expanded(child: Text('API key is sent only to the configured HTTPS backend during secure login.')),
                    SizedBox(width: 10),
                    Text('MASKED', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : login,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(busy ? 'CONNECTING...' : 'SECURE LOGIN'),
                  ),
                ),
              ),
              if (widget.status.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(widget.status),
              ],
              const SizedBox(height: 8),
              Text(
                'Vandana2 backend → Angel One SmartAPI → JWT + Feed Token → WebSocket 2.0',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          title: const Text('BACKEND CONNECTION'),
          subtitle: Text(widget.backendUrl),
          trailing: Icon(
            widget.connection == 'Connected' ? Icons.check_circle : Icons.cloud_off,
            color: widget.connection == 'Connected' ? Colors.green : Colors.orange,
          ),
        ),
      ),
    ],
  );
}
