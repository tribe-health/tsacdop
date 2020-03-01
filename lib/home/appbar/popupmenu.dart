import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:tsacdop/class/fireside_data.dart';
import 'package:xml/xml.dart' as xml;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:color_thief_flutter/color_thief_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:tsacdop/class/podcast_group.dart';
import 'package:tsacdop/settings/settting.dart';
import 'about.dart';
import 'package:tsacdop/class/podcastlocal.dart';
import 'package:tsacdop/local_storage/sqflite_localpodcast.dart';
import 'package:tsacdop/class/importompl.dart';
import 'package:tsacdop/webfeed/webfeed.dart';

class OmplOutline {
  final String text;
  final String xmlUrl;
  OmplOutline({this.text, this.xmlUrl});

  factory OmplOutline.parse(xml.XmlElement element) {
    if (element == null) return null;
    return OmplOutline(
      text: element.getAttribute("text")?.trim(),
      xmlUrl: element.getAttribute("xmlUrl")?.trim(),
    );
  }
}

class PopupMenu extends StatelessWidget {
  Future<String> getColor(File file) async {
    final imageProvider = FileImage(file);
    var colorImage = await getImageFromProvider(imageProvider);
    var color = await getColorFromImage(colorImage);
    String primaryColor = color.toString();
    return primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    ImportOmpl importOmpl = Provider.of<ImportOmpl>(context, listen: false);
    GroupList groupList = Provider.of<GroupList>(context, listen: false);
    _refreshAll() async {
      var dbHelper = DBHelper();
      List<PodcastLocal> podcastList = await dbHelper.getPodcastLocalAll();
      await Future.forEach(podcastList, (podcastLocal) async {
        importOmpl.rssTitle = podcastLocal.title;
        importOmpl.importState = ImportState.parse;
        await dbHelper.updatePodcastRss(podcastLocal);
        print('Refresh ' + podcastLocal.title);
      });
      importOmpl.importState = ImportState.complete;
    }

    saveOmpl(String rss) async {
      var dbHelper = DBHelper();
      importOmpl.importState = ImportState.import;

      Response response = await Dio().get(rss);
      if (response.statusCode == 200) {
        var _p = RssFeed.parse(response.data);
        
        var dir = await getApplicationDocumentsDirectory();
        
        String _realUrl = response.redirects.isEmpty ? rss : response.realUri.toString();
          
        print(_realUrl);
        bool _checkUrl = await dbHelper.checkPodcast(_realUrl);

        if (_checkUrl) {
          Response<List<int>> imageResponse = await Dio().get<List<int>>(
              _p.itunes.image.href,
              options: Options(responseType: ResponseType.bytes));
          img.Image image = img.decodeImage(imageResponse.data);
          img.Image thumbnail = img.copyResize(image, width: 300);
          String _uuid = Uuid().v4();
          File("${dir.path}/$_uuid.png")
            ..writeAsBytesSync(img.encodePng(thumbnail));
          
          String _imagePath = "${dir.path}/$_uuid.png";
          String _primaryColor = await getColor(File("${dir.path}/$_uuid.png"));
          String _author = _p.itunes.author ?? _p.author ?? '';
          String _provider = _p.generator ?? '';
          String _link = _p.link ?? '';
          PodcastLocal podcastLocal = PodcastLocal(
              _p.title,
              _p.itunes.image.href,
              _realUrl,
              _primaryColor,
              _author,
              _uuid,
              _imagePath,
              _provider,
              _link);

          podcastLocal.description = _p.description;

          await groupList.subscribe(podcastLocal);

          if (_provider.contains('fireside')) 
          {
            FiresideData data = FiresideData(_uuid, _link);
            await data.fatchData();
          }

          importOmpl.importState = ImportState.parse;

          await dbHelper.savePodcastRss(_p, _uuid);

          importOmpl.importState = ImportState.complete;
        } else {
          importOmpl.importState = ImportState.error;

          Fluttertoast.showToast(
            msg: 'Podcast Subscribed Already',
            gravity: ToastGravity.TOP,
          );
          await Future.delayed(Duration(seconds: 5));
          importOmpl.importState = ImportState.stop;
        }
      } else {
        importOmpl.importState = ImportState.error;

        Fluttertoast.showToast(
          msg: 'Network error, Subscribe failed',
          gravity: ToastGravity.TOP,
        );
        await Future.delayed(Duration(seconds: 5));
        importOmpl.importState = ImportState.stop;
      }
    }

    void _saveOmpl(String path) async {
      File file = File(path);
      String opml = file.readAsStringSync();

      var content = xml.parse(opml);
      var total = content
          .findAllElements('outline')
          .map((ele) => OmplOutline.parse(ele))
          .toList();
      if (total.length == 0) {
        Fluttertoast.showToast(
          msg: 'File Not Valid',
          gravity: ToastGravity.BOTTOM,
        );
      } else {
        for (int i = 0; i < total.length; i++) {
          if (total[i].xmlUrl != null) {
            importOmpl.rssTitle = total[i].text;
            try {
              await saveOmpl(total[i].xmlUrl);
            } catch (e) {
              print(e.toString());
            }
            print(total[i].text);
          }
        }
        print('Import fisnished');
      }
    }

    void _getFilePath() async {
      try {
        String filePath = await FilePicker.getFilePath(type: FileType.ANY);
        if (filePath == '') {
          return;
        }
        print('File Path' + filePath);
        importOmpl.importState = ImportState.start;
        _saveOmpl(filePath);
      } on PlatformException catch (e) {
        print(e.toString());
      }
    }

    return PopupMenuButton<int>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      elevation: 1,
      tooltip: 'Menu',
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 1,
          child: Container(
            padding: EdgeInsets.only(left: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.refresh),
                Padding(padding: EdgeInsets.symmetric(horizontal: 5.0),),
                Text('Refresh All'),
              ],
            ),
          ),
        ),
      PopupMenuItem(
            value: 2,
            child: Container(
              padding: EdgeInsets.only(left: 10),
              child: Row(
                children: <Widget>[
                  Icon(Icons.attachment),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 5.0),),
                  Text('Import OMPL'),
                ],
              ),
            ),
          ),
        
      //  PopupMenuItem(
      //    value: 3,
      //    child: setting.theme != 2 ? Text('Night Mode') : Text('Light Mode'),
      //  ),
         PopupMenuItem(
          value: 4,
          child: Container(
            padding: EdgeInsets.only(left: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.swap_calls),
                Padding(padding: EdgeInsets.symmetric(horizontal: 5.0),),
                Text('Settings'),
              ],
            ),
          ),
        ),
        PopupMenuItem(
          value: 5,
          child: Container(
            padding: EdgeInsets.only(left: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline),
                Padding(padding: EdgeInsets.symmetric(horizontal: 5.0),),
                Text('About'),
              ],
            ),
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 5) {
          Navigator.push(
              context, MaterialPageRoute(builder: (context) => AboutApp()));
        } else if (value == 2) {
          _getFilePath();
        } else if (value == 1) {
          _refreshAll();
        } else if (value == 3) {
        //  setting.theme != 2 ? setting.setTheme(2) : setting.setTheme(1);
        }  else if (value == 4) {
            Navigator.push(
              context, MaterialPageRoute(builder: (context) => Settings()));
        } 
      },
    );
  }
}