package {
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestMethod;
    import flash.net.URLRequestHeader;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;

    public class EspControl {

        private var deviceIP:String;
        // Простая "анти-дребезг" отправки: если быстро приходят команды, ждём и шлём по одной на тип.
        private var debounceDelay:int = 300; // мс — задержка для группировки команд
        private var debounceTimer:uint = 0;
        private var pendingQueue:Array = []; // элементы: {data,onComplete,onError,preTurnOff}

        public function EspControl(deviceIP:String) {
            this.deviceIP = deviceIP;
            //trace("[ESP] Controller initialized for device: " + deviceIP);
        }

        //-----------------------------
        // Logging helper
        //-----------------------------
        private function log(msg:String):void {
            var now:Date = new Date();
            var hh:String = (now.hours < 10 ? "0" : "") + now.hours;
            var mm:String = (now.minutes < 10 ? "0" : "") + now.minutes;
            var ss:String = (now.seconds < 10 ? "0" : "") + now.seconds;
            var ms:String = now.milliseconds.toString();
            while (ms.length < 3) ms = "0" + ms;
            trace("[" + hh + ":" + mm + ":" + ss + "." + ms + "][ESP] " + msg);
        }

        //-----------------------------
        // Base JSON POST sender
        //-----------------------------
        public function sendJson(data:Object,
                                 onComplete:Function = null,
                                 onError:Function = null,
                                 preTurnOff:Boolean = true,
                                 skipDebounce:Boolean = false):void {
            if (skipDebounce) {
                sendJsonNow(data, onComplete, onError, preTurnOff);
                return;
            }

            var cmdKey:String = data && data.hasOwnProperty("cmd") ? String(data["cmd"]) : "";

            // Если приходит обычная команда — очищаем очередь, чтобы ушла только она.
            // Для rooms_on/rooms_off оставляем оба, но сбрасываем остальные.
            if (cmdKey == "rooms_on" || cmdKey == "rooms_off") {
                var filtered:Array = [];
                for each (var keep:Object in pendingQueue) {
                    if (keep && keep.data && (keep.data.cmd == "rooms_on" || keep.data.cmd == "rooms_off")) {
                        filtered.push(keep);
                    }
                }
                pendingQueue = filtered;
            } else {
                pendingQueue = [];
            }

            // Накапливаем последнюю команду каждого типа (cmd) и ждём debounceDelay
            var replaced:Boolean = false;
            for (var i:int = 0; i < pendingQueue.length; i++) {
                var item:Object = pendingQueue[i];
                if (item && item.data && item.data.cmd == cmdKey) {
                    pendingQueue[i] = { data: data, onComplete: onComplete, onError: onError, preTurnOff: preTurnOff };
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                pendingQueue.push({ data: data, onComplete: onComplete, onError: onError, preTurnOff: preTurnOff });
            }

            if (debounceTimer != 0) {
                clearTimeout(debounceTimer);
            }
            debounceTimer = setTimeout(function():void {
                debounceTimer = 0;
                // Отправляем накопленные команды по порядку добавления/замены
                for each (var entry:Object in pendingQueue) {
                    if (entry && entry.data) {
                        sendJsonNow(entry.data, entry.onComplete, entry.onError, entry.preTurnOff);
                    }
                }
                pendingQueue = [];
            }, debounceDelay);
        }

        //-----------------------------
        // Batch sender
        //-----------------------------
        public function sendBatch(commands:Array,
                                  onComplete:Function = null,
                                  onError:Function = null,
                                  preTurnOff:Boolean = false,
                                  skipDebounce:Boolean = false):void {
            if (!commands || commands.length == 0) {
                log("batch: empty commands");
                return;
            }
            var payload:Object = { cmd: "batch", commands: commands };
            sendJson(payload, onComplete, onError, preTurnOff, skipDebounce);
        }

        private function sendJsonNow(data:Object,
                                     onComplete:Function = null,
                                     onError:Function = null,
                                     preTurnOff:Boolean = true):void {
            if (preTurnOff) {
                // Сначала ждём ответа от all_off, затем отправляем основную команду
                sendJsonInternal(
                    { cmd: "all_off", effect: "instant" },
                    function(_:*=null):void {
                        sendJsonInternal(data, onComplete, onError);
                    },
                    function(err:String):void {
                        log("Pre all_off error: " + err + " -> продолжаем с основной командой");
                        sendJsonInternal(data, onComplete, onError);
                    }
                );
            } else {
                sendJsonInternal(data, onComplete, onError);
            }
        }

        private function sendJsonInternal(data:Object,
                                          onComplete:Function = null,
                                          onError:Function = null):void {

            var jsonString:String = JSON.stringify(data);
            var url:String = deviceIP + "/";

            var cmdLabel:String = "";
            if (data && data.hasOwnProperty("cmd")) {
                cmdLabel = String(data["cmd"]);
            }
            log("Sending request, cmd=" + cmdLabel);

            var request:URLRequest = new URLRequest(url);
            request.method = URLRequestMethod.POST;
            request.data = jsonString;
            request.requestHeaders.push(new URLRequestHeader("Content-Type", "application/json"));

            var loader:URLLoader = new URLLoader();

            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                log("Response received");
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

            log("Turn ON apartment");

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

            // Для одиночной квартиры не отправляем предварительный all_off
            sendJson(payload, onComplete, onError, false);
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

            log("Turn ON apartment custom color");

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

            // Для одиночной квартиры не отправляем предварительный all_off
            sendJson(payload, onComplete, onError, false);
        }

        //-----------------------------
        // Turn ON whole floor (using floor_on)
        //-----------------------------
        public function floorOn(floor:int,
                                color:Array = null,
                                brightness:int = 255,
                                effect:String="instant",
                                onComplete:Function=null,
                                onError:Function=null):void {

            if (color == null) color = [255, 255, 255];
            if (brightness < 0 || brightness > 255) brightness = 255;

            log("Turn ON floor via floor_on");

            var payload:Object = {
                cmd: "floor_on",
                floor: floor,
                color: color,
                brightness: brightness,
                effect: effect
            };

            sendJson(payload, onComplete, onError);
        }

        //-----------------------------
        // Turn ON multiple rooms in one JSON (batch structure)
        //-----------------------------
        public function turnOnRoomsBatch(apartmentIds:Array,
                                         effect:String="instant",
                                         onComplete:Function=null,
                                         onError:Function=null,
                                         preTurnOff:Boolean=true,
                                         skipDebounce:Boolean=false):void {
            var payload:Object = buildRoomsOnCommand(apartmentIds, effect);
            if (!payload) return;
            log("Turn ON rooms batch");
            sendJson(payload, onComplete, onError, preTurnOff, skipDebounce);
        }

        //-----------------------------
        // Turn OFF multiple rooms in one JSON (batch structure)
        //-----------------------------
        public function turnOffRoomsBatch(apartmentIds:Array,
                                          effect:String="instant",
                                          onComplete:Function=null,
                                          onError:Function=null,
                                          preTurnOff:Boolean=false,
                                          skipDebounce:Boolean=false):void {
            var payload:Object = buildRoomsOffCommand(apartmentIds, effect);
            if (!payload) return;
            log("Turn OFF rooms batch");
            // Явно отключаем предварительный all_off, т.к. сами управляем списками
            sendJson(payload, onComplete, onError, preTurnOff, skipDebounce);
        }

        //-----------------------------
        // Helpers to build rooms_on / rooms_off payloads
        //-----------------------------
        public function buildRoomsOnCommand(apartmentIds:Array, effect:String="instant"):Object {
            if (!apartmentIds || apartmentIds.length == 0) {
                log("buildRoomsOnCommand: empty apartmentIds");
                return null;
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

            return {
                cmd: "rooms_on",
                rooms: rooms
            };
        }

        public function buildRoomsOffCommand(apartmentIds:Array, effect:String="instant"):Object {
            if (!apartmentIds || apartmentIds.length == 0) {
                log("buildRoomsOffCommand: empty apartmentIds");
                return null;
            }
            var rooms:Array = [];
            for each (var aptId:String in apartmentIds) {
                rooms.push(int(aptId));
            }
            return {
                cmd: "rooms_off",
                effect: effect,
                rooms: rooms
            };
        }

        //-----------------------------
        // Turn ON all LEDs a single color
        //-----------------------------
        public function turnOnAll(color:Array,
                                  brightness:int = 255,
                                  effect:String="instant",
                                  onComplete:Function=null,
                                  onError:Function=null):void {

            log("Turn ON ALL LEDs");

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

            log("Turn OFF ALL LEDs");

            var payload:Object = {
                cmd: "all_off",
                effect: "instant"
            };

            sendJson(payload, onComplete, onError, false);
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
