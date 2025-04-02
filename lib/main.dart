import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class EauPotableApi {
  final String rootPath =
      'https://hubeau.eaufrance.fr/api/v1/qualite_eau_potable/resultats_dis';
  final Dio dio = Dio();

  Future<List<dynamic>> getResultsByDepartement(String departement) async {
    try {
      final response = await dio.get(
        rootPath,
        queryParameters: {
          'format': 'json',
          'size': 10000,
          'code_parametre_se': ["NH4","CL2TOT","PH"],
          'nom_departement': departement,
        },
      );
      return response.data['data'];
    } catch (e) {
      print('Erreur (getResultsByDepartement) : $e');
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
  List<String> _availableYears = [];

  String? _selectedParametre;
  String? _selectedYear;
  String _error = '';

  LatLng? _selectedPosition;
  final MapController _mapController = MapController();

  List<dynamic> _allResults = [];

  void fetchInitialResults(String departement) async {
    setState(() {
      _error = '';
      _filteredResults = [];
      _availableParametres = [];
      _availableYears = [];
      _selectedParametre = null;
      _selectedYear = null;
    });

    if (departement.trim().isEmpty) {
      setState(() => _error = 'Veuillez entrer un nom de département.');
      return;
    }

    try {
      final results = await api.getResultsByDepartement(departement.trim());

      if (results.isEmpty) {
        setState(() => _error = 'Aucune donnée trouvée pour ce département.');
        return;
      }

      _allResults = results;

      final parametres = results
          .map((e) => e['libelle_parametre'])
          .whereType<String>()
          .toSet()
          .toList();

      setState(() {
        _availableParametres = parametres;
        if (parametres.isEmpty) {
          _error = 'Aucun paramètre trouvé pour ce département.';
        }
      });
    } catch (e) {
      setState(() => _error = 'Erreur lors du chargement des données.');
      print("Erreur fetchInitialResults: $e");
    }
  }


  void onParametreSelected(String? param) {
    setState(() {
      _selectedParametre = param;
      _selectedYear = null;
      _availableYears = [];
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
      setState(() => _availableYears = years);
      if (years.isEmpty) {
        setState(() => _error =
        'Aucune date disponible pour ce paramètre dans ce département.');
      } else {
        setState(() => _error = '');
      }
    }
  }

  void onYearSelected(String? year) {
    setState(() {
      _selectedYear = year;
      _filteredResults = [];
    });
    if (year != null && _selectedParametre != null) {
      final results = _allResults.where((e) {
        final date = e['date_prelevement'];
        return e['libelle_parametre'] == _selectedParametre &&
            date != null &&
            date.toString().startsWith(year);
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
        appBar:AppBar(
          title: const Text("Qualité de l'eau - Recherche"),
          centerTitle: true,
        ),
        body: Row(
          children: [
            // 🗺️ Carte interactive
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(17.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter:
                        LatLng(46.603354, 1.888334), // Centre France
                        initialZoom: 5.5,
                        onTap: (tapPosition, point) async {
                          setState(() {
                            _selectedPosition = point; // mets à jour le marker
                          });
                          //_mapController.move(point, 7.5); // a enlever si on veut pas que ca s'actualise

                          final lat = point.latitude;
                          final lon = point.longitude;

                          final url = Uri.parse(
                              'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json');

                          try {
                            final response = await http.get(url, headers: {
                              'User-Agent':
                              'FlutterApp (bdelaverny@gmail.com)' // obligatoire pour Nominatim
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
                              fetchInitialResults(departement); // lance la recherche
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
                      onPressed:  () {
                        fetchInitialResults(_deptController.text);
                      },
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
                    if (_selectedParametre != null)
                      DropdownButton<String>(
                        value: _selectedYear,
                        hint: const Text('Choisir une année'),
                        isExpanded: true,
                        items: _availableYears.map((year) {
                          return DropdownMenuItem(
                            value: year,
                            child: Text(year),
                          );
                        }).toList(),
                        onChanged: onYearSelected,
                        dropdownColor: _availableYears.isEmpty
                            ? Colors.red.shade100
                            : null,
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