import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class EauPotableApi {
  final String rootPath =
      'https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis';
  final Dio dio = Dio();

  Future<List<dynamic>> getResults(
      codeCommune, dateMin, dateMax, parametre) async {
    try {
      final response = await dio.get(
        rootPath,
        queryParameters: {
          'format': 'json',
          'code_commune': codeCommune,
          'code_parametre_se': parametre,
          'size': 10000,
          'date_min_prelevement': dateMin,
          'date_max_prelevement': dateMax,
        },
      );
      return response.data['data'];
    } catch (e) {
      print('Erreur : $e');
      return [];
    }
  }
}

Future<String?> getCodeInsee(String ville) async {
  final nomEncode = Uri.encodeQueryComponent(ville);

  final url = Uri.parse(
      'https://geo.api.gouv.fr/communes?nom=$nomEncode&fields=code,nom&format=json');

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    if (data is List && data.isNotEmpty) {
      print('🔍 Résultats Geo API:');
      for (var commune in data) {
        print(' - ${commune["nom"]} (${commune["code"]})');
      }

      final correspondance = data.firstWhere(
        (commune) => normalize(commune['nom']) == normalize(ville),
        orElse: () => null,
      );
      return correspondance != null ? correspondance['code'] : null;
    }
  }

  return null;
}

String normalize(String input) {
  return input
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'ç'), 'c');
}

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final EauPotableApi api = EauPotableApi();
  final TextEditingController _communeController = TextEditingController();

  List<Map<String, dynamic>> _filteredResults = [];

  String? _yearSelected;
  String? _monthSelected;
  bool _isLoading = false;
  String? _selectedParametre;
  String _error = '';

  final Map<String, String> months = {
    "Janvier": "01",
    "Février": "02",
    "Mars": "03",
    "Avril": "04",
    "Mai": "05",
    "Juin": "06",
    "Juillet": "07",
    "Août": "08",
    "Septembre": "09",
    "Octobre": "10",
    "Novembre": "11",
    "Décembre": "12",
  };

  List<ChartData> _chartData = [];

  final Map<String, String> parametres = {
    "pH": "PH",
    "Ammonium": "NH4",
    "Chlore": "CL2TOT",
  };

  final Map<String, double> seuilsMax = {
    "PH": 9.5,
    "NH4": 0.5,
    "CL2TOT": 0.5,
  };

  final List<String> years = [
    for (int year = 2025; year >= 2019; year--) year.toString()
  ];

  late TooltipBehavior _tooltipBehavior;
  LatLng? _selectedPosition;
  final MapController _mapController = MapController();

  //Map<String, List<LatLng>> _allDeptContours = {};
  List<Polygon> _visiblePolygons = [];

  @override
  void initState() {
    _communeController.addListener(_tryFetchResults);
    _tooltipBehavior = TooltipBehavior(enable: true);
    super.initState();
  }

  void fetchResults() async {
    setState(() {
      _error = '';
      _filteredResults = [];
      _isLoading = true;

    });
    print(seuilsMax[_selectedParametre]);

    List<dynamic> results = [];
    final nom = _communeController.text.trim();
    final codeInsee = await getCodeInsee(nom);

    if (_yearSelected != null &&
        codeInsee != null &&
        _selectedParametre != null &&
        _monthSelected != null) {
      try {
        final int year = int.parse(_yearSelected!);
        final int month = int.parse(_monthSelected!);
        final lastDay = DateTime(year, month + 1, 0).day;

        results = await api.getResults(
          codeInsee,
          '$_yearSelected-$_monthSelected-01%2000%3A00%3A00',
          '$_yearSelected-$_monthSelected-${lastDay.toString()}%2023%3A59%3A59',
          _selectedParametre,
        );

        if (results.isEmpty) {
          setState(() => _error =
              'Pas de résultats disponibles pour les paramètres choisis.');
        }
        //updateVisibleContour(_deptController.text);
      } catch (e) {
        setState(() => _error = 'Erreur lors du chargement des données.');
      }
    } else {
      setState(() => _error =
          'Erreur de chargement, veuillez renseigner tous les paramètres.');
    }

    setState(() {
      _isLoading = false;
    });

    final filtered = <Map<String, dynamic>>[];
    for (var result in results) {
      filtered.add({
        'libelle_parametre': result['libelle_parametre'],
        'date_prelevement': result['date_prelevement'],
        'nom_commune': result['nom_commune'],
        'resultat_numerique': result['resultat_numerique'],
        'conclusion': result['conclusion_conformite_prelevement']
      });
    }

    setState(() => _filteredResults = filtered);
    List<ChartData> chartData = [];
    String? lastDate;

    _filteredResults.removeWhere((element) => element["resultat_numerique"] == null);

    for (int i = 0; i < _filteredResults.length;) {
      final currentDate = _filteredResults[i]["date_prelevement"];

      if (currentDate == lastDate) {
        _filteredResults.removeAt(i);
      }
      else {
        lastDate = currentDate;
        i++;
      }
    }
    for (int i = 0; i < _filteredResults.length;i++) {
      chartData.add(ChartData(
        _filteredResults[i]['date_prelevement'],
        _filteredResults[i]['resultat_numerique'],
      ));
    }
    setState(() => _chartData = chartData);

    if (_chartData.length==1 || _chartData.isEmpty) {
      setState(() =>
      _error = "Pas assez de données disponibles pour tracer un graphe.");
    }
  }

  void _tryFetchResults() {
    final nom = _communeController.text.trim();
    if (_yearSelected != null &&
        _monthSelected != null &&
        _selectedParametre != null &&
        nom.isNotEmpty) {
      fetchResults();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Qualité de l'eau potable - Recherche"),
          centerTitle: true,
          backgroundColor: Colors.lightBlueAccent,
          foregroundColor: Colors.white,
          //elevation: 100,
          leading: IconTheme(
            data: IconThemeData(
              color: Colors.white,
              size: 30,
            ),
            child: Icon(Icons.water_drop),
          ),
        ),
        body: Row(
          children: [
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(3.0),
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                                'User-Agent':
                                    'FlutterApp (bdelaverny@gmail.com)'
                              });

                              if (response.statusCode == 200) {
                                final data = json.decode(response.body);
                                final address = data['address'];
                                //final departement = address['county'] ?? address['state_district'] ?? address['state'] ?? 'Département inconnu';
                                final commune =
                                    address["municipality"] ?? 'Ville inconnue';
                                print(
                                    "Adresse complète : ${jsonEncode(address)}");

                                setState(() {
                                  _communeController.text = commune;
                                });

                                print("Ville détecté : $commune");
                                //updateVisibleContour(departement);
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
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(3.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(children: [
                          TextField(
                            controller: _communeController,
                            decoration: const InputDecoration(
                              labelText: 'Entrez le nom de la ville',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 15),
                          SegmentedButton<String>(
                            segments: years.map((year) {
                              return ButtonSegment<String>(
                                value: year,
                                label: Text(year),
                              );
                            }).toList(),
                            selected:
                                _yearSelected != null ? {_yearSelected!} : {},
                            emptySelectionAllowed: true,
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() {
                                _yearSelected = newSelection.first;
                              });
                              _tryFetchResults();
                            },
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.lightBlueAccent;
                                }
                                return Colors.grey[255];
                              }),
                              foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return Colors.black87;
                              }),
                              shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              )),
                            ),
                          ),

                          const SizedBox(height: 15),
                          SegmentedButton<String>(
                            segments: months.entries.map((entry) {
                              final abbr =
                                  entry.key.substring(0, 3); // Ex: "Jan", "Fév"
                              return ButtonSegment<String>(
                                value: entry.value,
                                label: Text(abbr),
                              );
                            }).toList(),
                            selected:
                                _monthSelected != null ? {_monthSelected!} : {},
                            emptySelectionAllowed: true,
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() {
                                _monthSelected = newSelection.first;
                              });
                              _tryFetchResults();
                            },
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.lightBlueAccent;
                                }
                                return Colors.grey[255];
                              }),
                              foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return Colors.black87;
                              }),
                              shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              )),
                            ),
                          ),

                          const SizedBox(height: 15),
                          SegmentedButton<String>(
                            segments: parametres.keys.map((label) {
                              return ButtonSegment<String>(
                                value: label,
                                label: Text(label),
                              );
                            }).toList(),
                            selected: _selectedParametre != null
                                ? {
                                    parametres.entries
                                        .firstWhere((e) =>
                                            e.value == _selectedParametre)
                                        .key
                                  }
                                : {},
                            emptySelectionAllowed:
                                true,
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() {
                                final label = newSelection.first;
                                _selectedParametre = parametres[label]!;

                              });
                              _tryFetchResults();
                            },
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.lightBlueAccent;
                                }
                                return Colors.grey[255];
                              }),
                              foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return Colors.black87;
                              }),
                              shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              )),
                            ),
                          ),

                          const SizedBox(height: 15),
                          //ElevatedButton(
                          //onPressed: fetchResults,
                          //child: const Text('Valider les choix'),
                          //),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 15),
                    _isLoading
                        ? LinearProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.lightBlueAccent))
                        : const SizedBox(height: 0),
                    if (_error.isNotEmpty)
                      Text(
                        _error,
                        style: const TextStyle(color: Colors.red,fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    if (_filteredResults.isNotEmpty && _chartData.length>1)

                      Flexible(
                        child: Card(
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SfCartesianChart(
                              legend: Legend(isVisible: true),
                              title: ChartTitle(
                                  text:
                                      'Niveau de ${_filteredResults[0]["libelle_parametre"]}'),
                              primaryXAxis: DateTimeAxis(
                                dateFormat: DateFormat('dd/MM - HH:mm'),
                                intervalType: DateTimeIntervalType.days,
                                edgeLabelPlacement: EdgeLabelPlacement.shift,
                                interval: 1,
                                maximumLabels: 5,
                                labelRotation: -45,
                              ),
                              primaryYAxis: NumericAxis(),
                              tooltipBehavior: _tooltipBehavior,
                              series: <CartesianSeries>[
                                LineSeries<ChartData, DateTime>(
                                  dataSource: _chartData,
                                  enableTooltip: true,
                                  xValueMapper: (ChartData data, _) =>
                                      DateTime.parse(data.date),
                                  yValueMapper: (ChartData data, _) =>
                                      data.value,
                                  color: Colors.lightBlueAccent,
                                  name:
                                      '${_filteredResults[0]["libelle_parametre"]}',
                                  markerSettings:
                                      MarkerSettings(isVisible: true),
                                ),
                                LineSeries<ChartData, DateTime>(
                                  dataSource: [
                                    ChartData(_chartData.first.date, seuilsMax[_selectedParametre]!),
                                    ChartData(_chartData.last.date, seuilsMax[_selectedParametre]!),
                                  ],
                                  xValueMapper: (ChartData data, _) => DateTime.parse(data.date),
                                  yValueMapper: (ChartData data, _) => data.value,
                                  color: Colors.red,
                                  name: 'Seuil maximum sanitaire',
                                  dashArray: <double>[5, 5],
                                  markerSettings: MarkerSettings(isVisible: false),
                                ),

                              ],
                            ),
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  final String date;
  final double value;

  ChartData(this.date, this.value);
}
