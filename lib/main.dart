import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter/services.dart';

Future<List<Polygon>> loadDepartementPolygons() async {
  final String geoJsonStr = await rootBundle.loadString('lib/assets/departements.geojson');
  final Map<String, dynamic> geoJson = jsonDecode(geoJsonStr);

  List<Polygon> polygons = [];

  for (var feature in geoJson['features']) {
    final geometry = feature['geometry'];
    if (geometry['type'] == 'Polygon') {
      final List coords = geometry['coordinates'][0];
      final List<LatLng> points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
      polygons.add(
        Polygon(
          points: points,
          color: const Color.fromARGB(50, 0, 0, 255),
          borderColor: const Color.fromARGB(255, 0, 0, 255),
          borderStrokeWidth: 1.5,
        ),
      );
    } else if (geometry['type'] == 'MultiPolygon') {
      for (var polygon in geometry['coordinates']) {
        final List coords = polygon[0];
        final List<LatLng> points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
        polygons.add(
          Polygon(
            points: points,
            color: const Color.fromARGB(50, 0, 0, 255),
            borderColor: const Color.fromARGB(255, 0, 0, 255),
            borderStrokeWidth: 1.5,
          ),
        );
      }
    }
  }

  return polygons;
}

class EauPotableApi {
  final String rootPath =
      'https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis';
  final Dio dio = Dio();

  Future<List<dynamic>> getResults(departement) async {
    try {
      final response = await dio.get(
        rootPath,
        queryParameters: {
          'format': 'json',
          'code_parametre_se': ["NH4", "CL2TOT", "PH"],
          'size': 5000,
          'date_min_prelevement': "2024-01-01%2000%3A00%3A00",
          'date_max_prelevement': "2024-12-31%2023%3A59%3A59",
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

  String? _selectedParametre;
  String _error = '';

  LatLng? _selectedPosition;
  final MapController _mapController = MapController();

  List<dynamic> _allResults = [];

  List<Polygon> _departementPolygons = []; // 👈 ajouté

  @override
  void initState() {
    super.initState();
    loadDepartementPolygons().then((polygons) {
      setState(() {
        _departementPolygons = polygons;
      });
    });
  }

  void fetchInitialResults() async {
    setState(() {
      _error = '';
      _filteredResults = [];
      _availableParametres = [];
      _selectedParametre = null;
    });
    try {
      final results = await api.getResults(_deptController.text.trim());
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
    } catch (e) {
      setState(() => _error = 'Erreur lors du chargement des données.');
    }
  }

  void onParametreSelected(String? param) {
    setState(() {
      _selectedParametre = param;
      _filteredResults = [];
    });
    if (param != null) {
      final filtered =
      _allResults.where((e) => e['libelle_parametre'] == param).toList();
      final years = filtered
          .map((e) => e['date_prelevement']?.toString().substring(0, 4))
          .whereType<String>()
          .toSet()
          .toList();
      if (years.isEmpty) {
        setState(() => _error =
        'Aucune date disponible pour ce paramètre dans ce département.');
      } else {
        setState(() => _error = '');
      }
    }
    setState(() {
      _filteredResults = [];
    });
    if (_selectedParametre != null) {
      final results = _allResults.where((e) {
        return e['libelle_parametre'] == _selectedParametre;
      }).toList();

      final seenUnits = <String>{};
      final filtered = <Map<String, dynamic>>[];

      for (var result in results) {
        final unit = result['libelle_unite'];
        if (unit != null && !seenUnits.contains(unit)) {
          seenUnits.add(unit);
          filtered.add({
            'libelle_unite': unit,
            'date_prelevement': result['date_prelevement'],
            'nom_commune': result['nom_commune'],
            'resultat_numerique': result['resultat_numerique'],
          });
        }
      }
      setState(() => _filteredResults = filtered);
    }
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
                              print("Adresse complète : ${jsonEncode(address)}");

                              setState(() {
                                _deptController.text = departement;
                              });

                              print("Département détecté : $departement");
                              fetchInitialResults();
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
                      PolygonLayer(polygons: _departementPolygons), // 👈 ajouté
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      child: const Text('Valider le département'),
                    ),
                    const SizedBox(height: 10),
                    if (_availableParametres.isNotEmpty)
                      DropdownButton<String>(
                        value: _selectedParametre,
                        hint: const Text('Choisir un paramètre danalyse'),
                        isExpanded: true,
                        items: _availableParametres.map((param) {
                          return DropdownMenuItem(
                            value: param,
                            child: Text(param),
                          );
                        }).toList(),
                        onChanged: onParametreSelected,
                      ),
                    const SizedBox(height: 10),
                    if (_error.isNotEmpty)
                      Text(_error, style: const TextStyle(color: Colors.red)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredResults.length,
                        itemBuilder: (context, index) {
                          final item = _filteredResults[index];
                          return ListTile(
                            title:
                            Text(item['libelle_unite'] ?? 'Unité inconnue'),
                            subtitle: Text(
                              'Commune : ${item['nom_commune'] ?? 'Inconnue'}\n'
                                  'Date prélèvement : ${item['date_prelevement'] ?? 'Non renseignée'}\n'
                                  'Résultat : ${item['resultat_numerique'] ?? 'N/A'}',
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SfCartesianChart(
                          title: ChartTitle(text: 'Half yearly sales analysis'),
                          primaryXAxis: CategoryAxis(),
                          series: <CartesianSeries>[
                            LineSeries<ChartData, String>(
                              dataSource: [
                                ChartData('Jan', 35),
                                ChartData('Feb', 28),
                                ChartData('Mar', 34),
                                ChartData('Apr', 32),
                                ChartData('May', 40)
                              ],
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
