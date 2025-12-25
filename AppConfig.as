package {
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class AppConfig {
        private static const CONFIG_NAME:String = "config.json";
        private static const DEFAULT_ESP_URL:String = "http://192.168.1.251";
        private static const DEFAULT_COLORS:Object = {
            "available": "#00FF00",
            "reserved": "#FFFF00",
            "occupied": "#FF0000",
            "closed for sale": "#FFFFFF"
        };
        private static var loaded:Boolean = false;
        private static var espUrl:String = DEFAULT_ESP_URL;
        private static var colors:Object = DEFAULT_COLORS;

        public static function getEspUrl():String {
            if (!loaded) {
                load();
            }
            return espUrl;
        }

        public static function getLedColorHex(status:String):String {
            return resolveColor(status).hex;
        }

        public static function getLedColorRGB(status:String):Array {
            return resolveColor(status).rgb;
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
                if (obj && obj.hasOwnProperty("colors") && obj.colors is Object) {
                    colors = obj.colors;
                } else {
                    colors = DEFAULT_COLORS;
                }
            } catch (e:Error) {
                trace("[AppConfig] Error loading config, using default:", e.message);
                espUrl = DEFAULT_ESP_URL;
                colors = DEFAULT_COLORS;
            }
        }

        private static function saveDefault(file:File):void {
            try {
                var fs:FileStream = new FileStream();
                fs.open(file, FileMode.WRITE);
                fs.writeUTFBytes(JSON.stringify({ esp_url: DEFAULT_ESP_URL, colors: DEFAULT_COLORS }));
                fs.close();
            } catch (e:Error) {
                trace("[AppConfig] Error writing default config:", e.message);
            }
        }

        private static function normalizeStatus(status:String):String {
            if (!status) return "";
            var key:String = status.toLowerCase();
            // Заменяем кириллическую "с" на латинскую, чтобы ловить опечатку "сlosed for sale"
            key = key.split("с").join("c");
            return key;
        }

        private static function resolveColor(status:String):Object {
            if (!loaded) {
                load();
            }
            var key:String = normalizeStatus(status);
            var value:* = null;
            if (colors && colors.hasOwnProperty(key) && colors[key] !== null && colors[key] !== undefined) {
                value = colors[key];
            } else if (DEFAULT_COLORS.hasOwnProperty(key)) {
                value = DEFAULT_COLORS[key];
            } else {
                value = "#FFFFFF";
            }

            var rgb:Array = asRGB(value);
            var hex:String = (value is Array) ? rgbToHex(rgb) : String(value);
            return { hex: hex, rgb: rgb };
        }

        private static function asRGB(value:*):Array {
            if (value is Array && (value as Array).length >= 3) {
                return clampRGB(value as Array);
            }
            return hexToRGB(String(value));
        }

        private static function clampRGB(arr:Array):Array {
            var r:int = clamp(int(arr[0]));
            var g:int = clamp(int(arr[1]));
            var b:int = clamp(int(arr[2]));
            return [r, g, b];
        }

        private static function clamp(n:int):int {
            if (n < 0) return 0;
            if (n > 255) return 255;
            return n;
        }

        private static function hexToRGB(hex:String):Array {
            if (!hex) return [255, 255, 255];
            hex = hex.replace("#", "");
            if (hex.length != 6) return [255, 255, 255];

            var r:int = parseInt(hex.substr(0, 2), 16);
            var g:int = parseInt(hex.substr(2, 2), 16);
            var b:int = parseInt(hex.substr(4, 2), 16);
            return [r, g, b];
        }

        private static function rgbToHex(rgb:Array):String {
            var r:int = clamp(int(rgb[0]));
            var g:int = clamp(int(rgb[1]));
            var b:int = clamp(int(rgb[2]));

            var sr:String = (r < 16 ? "0" : "") + r.toString(16).toUpperCase();
            var sg:String = (g < 16 ? "0" : "") + g.toString(16).toUpperCase();
            var sb:String = (b < 16 ? "0" : "") + b.toString(16).toUpperCase();
            return "#" + sr + sg + sb;
        }
    }
}
