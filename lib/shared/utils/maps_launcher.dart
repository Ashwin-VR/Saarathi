import 'package:url_launcher/url_launcher.dart';

Future<void> openInGoogleMaps(double lat, double lng) async {
  final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}
