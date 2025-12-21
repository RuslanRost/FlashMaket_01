package {
    public class LedController {

        private var esp:EspControl;

        public function LedController(espControl:EspControl) {
            this.esp = espControl;
        }

        //----------------------------------------------
        // Цвет как HEX → перевод в RGB Array для ESP
        //----------------------------------------------
        private function hexToRGB(hex:String):Array {
            hex = hex.replace("#", "");
            if (hex.length != 6) return [255, 255, 255];

            var r:int = parseInt(hex.substr(0, 2), 16);
            var g:int = parseInt(hex.substr(2, 2), 16);
            var b:int = parseInt(hex.substr(4, 2), 16);

            return [r, g, b];
        }

        //----------------------------------------------
        // Цвет по статусу (локальная логика для LedController)
        //----------------------------------------------
        private function getHexColorByStatus(status:String):String {
            switch(status) {
                case "Available": return "#00FF00";       // зелёный
                case "Reserved": return "#FFFF00";        // жёлтый
                case "Occupied": return "#FF0000";        // красный
                case "Closed for sale": return "#FFFFFF"; // белый
                default: return "#000000";                // чёрный
            }
        }

        //----------------------------------------------
        // Включение одной квартиры по статусу
        //----------------------------------------------
        public function lightUpRoomByStatus(roomId:String):void {
            var status:String = CRMData.getDataById(roomId, "status");

            if(status == null) {
                trace("[LED] Статус не найден для квартиры " + roomId);
                return;
            }

            trace("[LED] Подсветка квартиры по статусу → " + roomId);

            // Используем ESP функцию включения одной квартиры
            esp.turnOnApartment(roomId);
        }

        //----------------------------------------------
        // Включение одной квартиры конкретным цветом
        //----------------------------------------------
        public function lightUpRoom(roomId:String, color:String):void {
            trace("[LED] Подсветка квартиры " + roomId + " цветом " + color);

            var rgb:Array = hexToRGB(color);
            var brightness:* = CRMData.getDataById(roomId, "ledbrightness");
            var brightnessInt:int = (brightness !== null && brightness !== undefined && !isNaN(Number(brightness))) ? int(brightness) : -1;

            esp.turnOnApartmentWithColor(roomId, rgb, brightnessInt);
        }

        //----------------------------------------------
        // МИГАНИЕ ЭТАЖА - только расчёт, подсветку не меняем
        //----------------------------------------------
        public function blinkFloorByStatus(floorId:int):void {
            var apartments:Object = CRMData.getAllData();

            if(!apartments) {
                trace("[LED] Нет данных CRM");
                return;
            }

            var floor:String = floorId.toString();
            var colors:Object = {};
            var ids:Array = [];

            for (var id:String in apartments) {
                if (id.indexOf(floor) == 0) {
                    ids.push(id);
                    var status:String = CRMData.getDataById(id, "status");
                    if (status) {
                        var c:String = getHexColorByStatus(status);
                        colors[c] = (colors[c] == undefined) ? 1 : colors[c] + 1;
                    }
                }
            }

            var summary:String = "";
            for (var col:String in colors) summary += col + " x" + colors[col] + ", ";

            if (summary.length == 0) summary = "Нет квартир на этаже";
            else summary = summary.slice(0, -2);

            trace("[LED] Мигаем этажом " + floorId + ": " + summary);

            if (ids.length > 0) {
                // используем эффект blink через batch-команду
                esp.turnOnRoomsBatch(ids, "blink");
            }
        }

        //----------------------------------------------
        // Включить ЭТАЖ по статусам
        //----------------------------------------------
        public function lightUpFloor(floor:int):void {

            var apartments:Object = CRMData.getAllData();
            var floorId:String = floor.toString();
            var ids:Array = [];

            for (var apt:String in apartments) {
                if (apt.indexOf(floorId) == 0) {
                    ids.push(apt);
                }
            }

            if (ids.length == 0) {
                trace("[LED] Нет квартир на этаже " + floor);
                return;
            }

            trace("[LED] Подсветка этажа " + floor + " → " + ids.join(", "));

            // вызыаем ESP функцию включения этажа
            esp.turnOnFloor(ids);
        }

        //----------------------------------------------
        // Включить все текущие видимые (отфильтрованные) квартиры одним JSON
        //----------------------------------------------
        public function lightUpFilteredVisible():void {
            var buttons:Array = GlobalData.apartmentButtons;
            if (!buttons || buttons.length == 0) {
                trace("[LED] Нет кнопок квартир для подсветки отфильтрованных");
                return;
            }

            var ids:Array = [];
            for each (var btn:ApartmentButtonNew in buttons) {
                if (btn && btn.visible && btn.apartmentNumber) {
                    ids.push(btn.apartmentNumber);
                }
            }

            if (ids.length == 0) {
                trace("[LED] Нет видимых (отфильтрованных) квартир для подсветки");
                return;
            }

            trace("[LED] Подсветка видимых квартир → " + ids.join(", "));
            esp.turnOnRoomsBatch(ids);
        }

        //----------------------------------------------
        // Включить ВСЕ определённым цветом (HEX)
        //----------------------------------------------
        public function lightUpAll(colorHex:String):void {
            var rgb:Array = hexToRGB(colorHex);

            trace("[LED] Включаем ВСЕ светодиоды цветом " + colorHex);

            esp.turnOnAll(rgb);
        }

        //----------------------------------------------
        // Отключить ВСЕ
        //----------------------------------------------
        public function resetLighting():void {
            trace("[LED] Reset — выключаем все светодиоды");
            esp.turnOffAll();
        }

        //----------------------------------------------
        // Демонстрационные режимы (пока заглушки)
        //----------------------------------------------
        public function startRunningLights():void {
            trace("[LED] DEMO: Бегущие огни");
        }

        public function startFadeBlink():void {
            trace("[LED] DEMO: плавное мигание");
        }

        public function startCycleRoomTypes():void {
            trace("[LED] DEMO: циклическая подсветка типов");
        }

        public function startOccupancySimulation():void {
            trace("[LED] DEMO: имитация заселения");
        }

        public function stopDemo():void {
            trace("[LED] DEMO остановлен");
            esp.disableDemoMode();
        }

        //----------------------------------------------
        // v4 demo mode (контроллер сам мигает белым)
        //----------------------------------------------
        public function startDemoMode():void {
            trace("[LED] DEMO: включаем demo_mode");
            esp.enableDemoMode();
        }

        public function stopDemoMode():void {
            trace("[LED] DEMO: выключаем demo_mode");
            esp.disableDemoMode();
        }
    }
}
