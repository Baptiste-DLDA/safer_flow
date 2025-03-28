import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class HubEauFlow {
  final String rootPath = 'https://hubeau.eaufrance.fr/api/v1/ecoulement';
  final Dio dio = Dio();

  Future<List<dynamic>> getStations({
    String format = 'json',
    String? codeStation,
    String? libelleStation,
  }) async {
    try {
      final response = await dio.get(
        '$rootPath/stations',
        queryParameters: {
          'format': format,
          if (codeStation != null) 'code_station': codeStation,
          if (libelleStation != null) 'libelle_station': libelleStation,
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

class MyApp extends StatelessWidget {
  final HubEauFlow api = HubEauFlow();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('API HubEau Simplifiée')),
        body: FutureBuilder<List<dynamic>>(
          future: api.getStations(
            format: 'json',
            libelleStation: 'Var', // Exemple : chercher les stations avec "Loire"
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Erreur : ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('Aucune station trouvée.'));
            }

            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final station = snapshot.data![index];
                return ListTile(
                  title: Text(station['libelle_station'] ?? 'Nom inconnu'),
                  subtitle: Text('Code: ${station['code_station'] ?? 'Inconnu'}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
