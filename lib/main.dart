import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter/services.dart';

// push pour montrer à ma mère

Future<Map<String, List<LatLng>>> loadDepartementContours() async {
  final String geoJsonStr =
      await rootBundle.loadString('lib/assets/departements.geojson');
  final Map<String, dynamic> geoJson = jsonDecode(geoJsonStr);

  Map<String, List<LatLng>> contours = {};

  for (var feature in geoJson['features']) {
    final properties = feature['properties'];
    final nomDept = properties['nom']?.toString().toLowerCase();

    final geometry = feature['geometry'];
    if (geometry['type'] == 'Polygon') {
      final List coords = geometry['coordinates'][0];
      final List<LatLng> points =
          coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
      contours[nomDept!] = points;
    } else if (geometry['type'] == 'MultiPolygon') {
      final List<LatLng> mergedPoints = [];
      for (var polygon in geometry['coordinates']) {
        final List coords = polygon[0];
        mergedPoints.addAll(coords.map<LatLng>((c) => LatLng(c[1], c[0])));
      }
      contours[nomDept!] = mergedPoints;
    }
  }

  return contours;
}

class EauPotableApi {
  final String rootPath =
      'https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis';
  final Dio dio = Dio();

  Future<List<dynamic>> getResults(departement, dateMin, dateMax) async {
    try {
      final response = await dio.get(
        rootPath,
        queryParameters: {
          'format': 'json',
          'code_parametre_se': ["NH4", "CL2TOT", "PH"],
          'size': 20000,
          'date_min_prelevement': dateMin,
          'date_max_prelevement': dateMax,
          "nom_departement": departement
        },
      );
      return response.data['data'];
    } catch (e) {
      print('Erreur : $e');
      return [];
    }
  }
}

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final EauPotableApi api = EauPotableApi();
  final TextEditingController _deptController = TextEditingController();

  List<Map<String, dynamic>> _filteredResults = [];
  List<String> _availableParametres = [];

  Set<String> _yearSelected = {"2025"};
  bool _isLoading = false;
  String? _selectedParametre;
  String _error = '';

  List<ChartData> _chartData = [];

  LatLng? _selectedPosition;
  final MapController _mapController = MapController();

  List<dynamic> _allResults = [];
  Map<String, List<LatLng>> _allDeptContours = {};
  List<Polygon> _visiblePolygons = [];

  @override
  void initState() {
    super.initState();
    loadDepartementContours().then((contours) {
      setState(() {
        _allDeptContours = contours;
      });
    });
  }

  void updateVisibleContour(String? nomDept) {
    if (nomDept == null) return;

    final key = nomDept.trim().toLowerCase();
    if (_allDeptContours.containsKey(key)) {
      final points = _allDeptContours[key]!;
      setState(() {
        _visiblePolygons = [
          Polygon(
            points: points,
            color: const Color.fromARGB(40, 0, 255, 0),
            borderColor: const Color.fromARGB(255, 0, 150, 0),
            borderStrokeWidth: 2,
          )
        ];
      });
    } else {
      setState(() => _visiblePolygons = []);
    }
  }

  void fetchInitialResults() async {
    setState(() {
      _error = '';
      _filteredResults = [];
      _availableParametres = [];
      _selectedParametre = null;
      _isLoading = true;
    });
    try {
      final results = await api.getResults(
          _deptController.text.trim(),
          '${_yearSelected.first}-01-01%2000%3A00%3A00',
          '${_yearSelected.first}-12-31%2023%3A59%3A59');
      final inputDept = _deptController.text.trim().toLowerCase();
      final deptResults = results
          .where((r) =>
              r['nom_departement']?.toString().toLowerCase() == inputDept)
          .toList();

      _allResults = deptResults;

      final parametres = deptResults
          .map((e) => e['libelle_parametre'])
          .whereType<String>()
          .toSet()
          .toList();
      setState(() => _availableParametres = parametres);

      if (parametres.isEmpty) {
        setState(() => _error = 'Aucun paramètre trouvé pour ce département.');
      }

      updateVisibleContour(_deptController.text);
    } catch (e) {
      setState(() => _error = 'Erreur lors du chargement des données.');
    }
    setState(() {
      _isLoading = false;
    });
  }

  void onParametreSelected(String? param) {
    setState(() {
      _selectedParametre = param;
      _filteredResults = [];
    });
    List<ChartData> chartData = [];
    if (param != null) {
      final results =
          _allResults.where((e) => e['libelle_parametre'] == param).toList();

      final filtered = <Map<String, dynamic>>[];
      for (var result in results) {
        filtered.add({
          'libelle_parametre': result['libelle_parametre'],
          'date_prelevement': result['date_prelevement'],
          'nom_commune': result['nom_commune'],
          'resultat_numerique': result['resultat_numerique'],
        });
      }
      setState(() => _filteredResults = filtered);
    }
    for (var i = 0; i < _filteredResults.length; i++) {
      chartData.add(ChartData(
        _filteredResults[i]['date_prelevement'],
        _filteredResults[i]['resultat_numerique'],
      ));
    }
    setState(() => _chartData = chartData);
  }



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
            title: const Text("Qualité de l'eau - Recherche"),
            centerTitle: true),
        body: Row(
          children: [
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter: LatLng(46.603354, 1.888334),
                        initialZoom: 5.5,
                        onTap: (tapPosition, point) async {
                          setState(() {
                            _selectedPosition = point;
                          });

                          final lat = point.latitude;
                          final lon = point.longitude;

                          final url = Uri.parse(
                              'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json');

                          try {
                            final response = await http.get(url, headers: {
                              'User-Agent': 'FlutterApp (bdelaverny@gmail.com)'
                            });

                            if (response.statusCode == 200) {
                              final data = json.decode(response.body);
                              final address = data['address'];
                              final departement = address['county'] ??
                                  address['state_district'] ??
                                  address['state'] ??
                                  'Département inconnu';
                              print(
                                  "Adresse complète : ${jsonEncode(address)}");

                              setState(() {
                                _deptController.text = departement;
                              });

                              print("Département détecté : $departement");
                              fetchInitialResults();
                              updateVisibleContour(departement);
                            } else {
                              print("Erreur API : ${response.statusCode}");
                            }
                          } catch (e) {
                            print("Erreur reverse geocoding : $e");
                          }
                        }),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        tileProvider: CancellableNetworkTileProvider(),
                      ),
                      PolygonLayer(polygons: _visiblePolygons),
                      if (_selectedPosition != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPosition!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: "2025",
                          label: Text("2025"),
                        ),
                        ButtonSegment(
                          value: "2024",
                          label: Text("2024"),
                        ),
                        ButtonSegment(
                          value: "2023",
                          label: Text("2023"),
                        ),
                        ButtonSegment(
                          value: "2022",
                          label: Text("2022"),
                        ),
                        ButtonSegment(
                          value: "2021",
                          label: Text("2021"),
                        ),
                        ButtonSegment(
                          value: "2020",
                          label: Text("2020"),
                        ),
                        ButtonSegment(
                          value: "2019",
                          label: Text("2019"),
                        ),
                      ],
                      selected: _yearSelected,
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _yearSelected = newSelection;
                        });
                      },
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _deptController,
                      decoration: const InputDecoration(
                        labelText: 'Entrez le nom du département',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: fetchInitialResults,
                      child: const Text('Valider les choix'),
                    ),
                    const SizedBox(height: 15),
                    _isLoading ? LinearProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)):
                    const SizedBox(height: 0),
                    if (_availableParametres.isNotEmpty)
                      DropdownButton<String>(
                        value: _selectedParametre,
                        hint: const Text("Choisir un paramètre d'analyse"),
                        isExpanded: true,
                        items: _availableParametres.map((param) {
                          return DropdownMenuItem(
                            value: param,
                            child: Text(param),
                          );
                        }).toList(),
                        onChanged: onParametreSelected,
                      ),

                    const SizedBox(height: 15),
                    if (_error.isNotEmpty)
                      Text(_error, style: const TextStyle(color: Colors.red)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredResults.length,
                        itemBuilder: (context, index) {
                          final item = _filteredResults[index];
                          return ListTile(
                            title: Text(
                                item['libelle_parametre'] ?? 'Unité inconnue'),
                            subtitle: Text(
                              'Commune : ${item['nom_commune'] ?? 'Inconnue'}\n'
                              'Date prélèvement : ${item['date_prelevement'] ?? 'Non renseignée'}\n'
                              'Résultat : ${item['resultat_numerique'] ?? 'N/A'}',
                            ),
                          );
                        },
                      ),
                    ),
                    if (_filteredResults.isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SfCartesianChart(
                            title: ChartTitle(
                                text:
                                    'Niveau de ${_filteredResults[0]["libelle_parametre"]}'),
                            primaryXAxis: CategoryAxis(),
                            series: <CartesianSeries>[
                              LineSeries<ChartData, String>(
                                dataSource: _chartData,
                                xValueMapper: (ChartData data, _) => data.x,
                                yValueMapper: (ChartData data, _) => data.y,
                              )
                            ],
                          ),
                        ),
                      )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class ChartData {
  ChartData(this.x, this.y);
  final String x;
  final double? y;
}
