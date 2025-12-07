package {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestMethod;
    import flash.net.URLRequestHeader;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class EspControl {

        private var deviceIP:String;

        public function EspControl(deviceIP:String) {
            this.deviceIP = deviceIP;
            //trace("[ESP] Controller initialized for device: " + deviceIP);
        }

        //-----------------------------
        // Logging helper
        //-----------------------------
        private function log(msg:String):void {
            trace("[ESP] " + msg);
        }

        //-----------------------------
        // Save JSON for debugging
        //-----------------------------
        private function saveJsonToFile(jsonString:String, fileName:String = "esp_debug.json"):void {
            try {
                var file:File = File.documentsDirectory.resolvePath(fileName);
                var stream:FileStream = new FileStream();
                stream.open(file, FileMode.WRITE);
                stream.writeUTFBytes(jsonString);
                stream.close();

                log("JSON saved to file: " + file.nativePath);
            } catch (error:Error) {
                log("ERROR saving JSON: " + error.message);
            }
        }

        //-----------------------------
        // Base JSON POST sender
        //-----------------------------
        public function sendJson(data:Object,
                                 onComplete:Function = null,
                                 onError:Function = null):void {

            var jsonString:String = JSON.stringify(data);
            var url:String = deviceIP + "/";

            log("------------------------------");
            log("Sending POST -> " + url);
            log("Payload: " + jsonString);

            saveJsonToFile(jsonString);

            var request:URLRequest = new URLRequest(url);
            request.method = URLRequestMethod.POST;
            request.data = jsonString;
            request.requestHeaders.push(new URLRequestHeader("Content-Type", "application/json"));

            var loader:URLLoader = new URLLoader();

            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                log("Response received: " + loader.data);
                if(onComplete != null) onComplete(loader.data);
            });

            loader.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
                log("IO ERROR: " + e.text);
                if(onError != null) onError("IO Error: " + e.text);
            });

            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent):void {
                log("SECURITY ERROR: " + e.text);
                if(onError != null) onError("Security Error: " + e.text);
            });

            try {
                loader.load(request);
            } catch(error:Error) {
                log("LOAD ERROR: " + error.message);
                if(onError != null) onError("Load Error: " + error.message);
            }
        }

        //-----------------------------
        // Get color by status
        //-----------------------------
        private function getColorByStatus(status:String):Array {
            if (!status) return [255, 255, 255];

            switch(status.toLowerCase()) {
                case "available":  return [0, 255, 0];
                case "reserved":   return [255, 255, 0];
                case "occupied":   return [255, 0, 0];
                case "сlosed for sale":
                case "closed for sale":
                    return [255, 255, 255];
            }
            return [255, 255, 255];
        }

        //-----------------------------
        // Get brightness or default 255
        //-----------------------------
        private function getBrightness(apartmentId:String):int {
            var value:* = CRMData.getDataById(apartmentId, "ledbrightness");
            if (value === null || value === undefined || isNaN(Number(value))) {
                return 255;
            }

            var brightness:int = int(value);
            if (brightness < 0) brightness = 0;
            if (brightness > 255) brightness = 255;
            return brightness;
        }

        //-----------------------------
        // Turn ON one apartment (status-based color)
        //-----------------------------
        public function turnOnApartment(apartmentId:String,
                                        effect:String="instant",
                                        onComplete:Function=null,
                                        onError:Function=null):void {

            var ledId:int = CRMData.getDataById(apartmentId, "LedID");
            var status:String = CRMData.getDataById(apartmentId, "status");
            var brightness:int = getBrightness(apartmentId);

            log("Turn ON apartment " + apartmentId + " -> LedID: " + ledId + ", status: " + status + ", brightness: " + brightness + ", effect: " + effect);

            if (!ledId) {
                log("ERROR: LedID not found for " + apartmentId);
                return;
            }

            var payload:Object = {
                cmd: "room_on",
                room: int(apartmentId),
                color: getColorByStatus(status),
                brightness: brightness,
                effect: effect
            };

            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Turn ON one apartment with custom color
        //-----------------------------
        public function turnOnApartmentWithColor(apartmentId:String,
                                                 color:Array,
                                                 brightness:int = -1,
                                                 effect:String="instant",
                                                 onComplete:Function=null,
                                                 onError:Function=null):void {

            var ledId:int = CRMData.getDataById(apartmentId, "LedID");
            var appliedBrightness:int = brightness;

            // If brightness not provided, fall back to CRM value
            if (brightness < 0 || brightness > 255) {
                appliedBrightness = getBrightness(apartmentId);
            }
            if (appliedBrightness < 0) appliedBrightness = 0;
            if (appliedBrightness > 255) appliedBrightness = 255;

            log("Turn ON apartment custom color " + apartmentId + " -> LedID: " + ledId + ", brightness: " + appliedBrightness + ", effect: " + effect);

            if (!ledId) {
                log("ERROR: LedID not found for " + apartmentId);
                return;
            }

            var payload:Object = {
                cmd: "room_on",
                room: int(apartmentId),
                color: color,
                brightness: appliedBrightness,
                effect: effect
            };

            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Turn ON whole floor
        //-----------------------------
        public function turnOnFloor(apartmentIds:Array,
                                    effect:String="instant",
                                    onComplete:Function=null,
                                    onError:Function=null):void {

            log("Turn ON floor. Apartments: " + apartmentIds.join(", "));

            turnOnRoomsBatch(apartmentIds, effect, onComplete, onError);
        }

        //-----------------------------
        // Turn ON multiple rooms in one JSON (batch structure)
        //-----------------------------
        public function turnOnRoomsBatch(apartmentIds:Array,
                                         effect:String="instant",
                                         onComplete:Function=null,
                                         onError:Function=null):void {
            if (!apartmentIds || apartmentIds.length == 0) {
                log("turnOnRoomsBatch: empty apartmentIds");
                return;
            }

            var rooms:Array = [];
            for each (var aptId:String in apartmentIds) {
                var status:String = CRMData.getDataById(aptId, "status");
                var brightness:int = getBrightness(aptId);
                var color:Array = getColorByStatus(status);

                rooms.push({
                    room: int(aptId),
                    color: color,
                    brightness: brightness,
                    effect: effect
                });
            }

            var payload:Object = {
                cmd: "rooms_on",
                rooms: rooms
            };

            log("Turn ON rooms batch: " + apartmentIds.join(","));
            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Turn ON all LEDs a single color
        //-----------------------------
        public function turnOnAll(color:Array,
                                  brightness:int = 255,
                                  effect:String="instant",
                                  onComplete:Function=null,
                                  onError:Function=null):void {

            log("Turn ON ALL LEDs, color=" + color);

            var payload:Object = {
                cmd: "all_on",
                color: color,
                brightness: brightness,
                effect: effect
            };

            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Turn OFF all LEDs
        //-----------------------------
        public function turnOffAll(effect:String="instant",
                                   onComplete:Function=null,
                                   onError:Function=null):void {

            log("Turn OFF ALL LEDs, effect=" + effect);

            var payload:Object = {
                cmd: "all_off",
                effect: effect
            };

            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Demo mode control
        //-----------------------------
        public function enableDemoMode(onComplete:Function=null,
                                       onError:Function=null):void {
            log("Enable demo mode");

            var payload:Object = {
                cmd: "demo_mode",
                mode: "on"
            };

            sendJson(payload, onComplete, onError);
        }

        public function disableDemoMode(onComplete:Function=null,
                                        onError:Function=null):void {
            log("Disable demo mode");

            var payload:Object = {
                cmd: "demo_mode",
                mode: "off"
            };

            sendJson(payload, onComplete, onError);
        }
    }
}
