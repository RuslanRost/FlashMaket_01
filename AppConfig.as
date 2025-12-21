package {
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class AppConfig {
        private static const CONFIG_NAME:String = "config.json";
        private static const DEFAULT_ESP_URL:String = "http://192.168.1.251";
        private static var loaded:Boolean = false;
        private static var espUrl:String = DEFAULT_ESP_URL;

        public static function getEspUrl():String {
            if (!loaded) {
                load();
            }
            return espUrl;
        }

        private static function load():void {
            loaded = true;
            try {
                var baseDir:File = File.applicationStorageDirectory;
                var crmFile:File = baseDir.resolvePath("crm_data.json");
                if (crmFile.exists && crmFile.parent) {
                    baseDir = crmFile.parent;
                }
                var file:File = baseDir.resolvePath(CONFIG_NAME);
                if (!file.exists) {
                    saveDefault(file);
                    return;
                }
                var fs:FileStream = new FileStream();
                fs.open(file, FileMode.READ);
                var raw:String = fs.readUTFBytes(fs.bytesAvailable);
                fs.close();
                var obj:Object = JSON.parse(raw);
                if (obj && obj.hasOwnProperty("esp_url") && obj.esp_url) {
                    espUrl = String(obj.esp_url);
                }
            } catch (e:Error) {
                trace("[AppConfig] Error loading config, using default:", e.message);
                espUrl = DEFAULT_ESP_URL;
            }
        }

        private static function saveDefault(file:File):void {
            try {
                var fs:FileStream = new FileStream();
                fs.open(file, FileMode.WRITE);
                fs.writeUTFBytes(JSON.stringify({ esp_url: DEFAULT_ESP_URL }));
                fs.close();
            } catch (e:Error) {
                trace("[AppConfig] Error writing default config:", e.message);
            }
        }
    }
}
