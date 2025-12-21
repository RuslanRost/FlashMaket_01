package {
    public class LedController {

        private var esp:EspControl;

        public function LedController(espControl:EspControl) {
            this.esp = espControl;
        }

        //----------------------------------------------
        // Цвет как HEX -> перевод в RGB Array для ESP
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
                default: return "#000000";                 // чёрный
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

            trace("[LED] Подсветка квартиры по статусу > " + roomId);

            // Используем ESP функцию включения одной квартиры
            esp.turnOnApartment(roomId, "pulse");
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
        // МИГАНИЕ ЭТАЖА - используем floor_on
        //----------------------------------------------
        public function blinkFloorByStatus(floorId:int):void {
            var apartments:Object = CRMData.getAllData();

            if (!apartments) {
                trace("[LED] Нет данных CRM");
                return;
            }

            var floor:String = floorId.toString();
            var hasAny:Boolean = false;

            for (var id:String in apartments) {
                if (id.indexOf(floor) == 0) {
                    hasAny = true;
                    break;
                }
            }

            if (!hasAny) {
                trace("[LED] Нет квартир на этаже " + floorId);
                return;
            }

            trace("[LED] Мигаем этажом через floor_on " + floorId);
            // Передаём effect=blink, остальные параметры по умолчанию
            esp.floorOn(floorId, null, 255, "blink3");
        }

        //----------------------------------------------
        // Включить ЭТАЖ по статусам
        //----------------------------------------------
        public function lightUpFloor(floor:int):void {

            var apartments:Object = CRMData.getAllData();
            var floorId:String = floor.toString();
            var hasAny:Boolean = false;

            for (var apt:String in apartments) {
                if (apt.indexOf(floorId) == 0) {
                    hasAny = true;
                    break;
                }
            }

            if (!hasAny) {
                trace("[LED] Нет квартир на этаже " + floor);
                return;
            }

            trace("[LED] Подсветка этажа (floor_on) " + floor);

            // API floor_on: передаём номер этажа (zero-based), остальные параметры дефолтные
            esp.floorOn(floor);
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
                // даже если видимых нет, всё равно нужно погасить остальные
            }

            // Собираем список невидимых квартир, чтобы отправить rooms_off без общего all_off
            var apartments:Object = CRMData.getAllData();
            var invisible:Array = [];
            var visibleSet:Object = {};
            for each (var vid:String in ids) visibleSet[vid] = true;

            // Определяем текущий этаж (по активной кнопке, иначе по первой видимой)
            var currentFloor:int = extractFloorNumber(GlobalData.activeButtonName);
            if (currentFloor < 0 && ids.length > 0) {
                currentFloor = extractFloorNumber(ids[0]);
            }

            for (var apt:String in apartments) {
                if (!visibleSet.hasOwnProperty(apt)) {
                    if (currentFloor >= 0) {
                        // Ограничиваемся только текущим этажом
                        if (extractFloorNumber(apt) != currentFloor) continue;
                    }
                    invisible.push(apt);
                }
            }

            if (ids.length > 0) {
                trace("[LED] Подсветка видимых квартир > " + ids.join(", "));
                esp.turnOnRoomsBatch(ids, "instant", null, null, false);
            }

            if (invisible.length > 0) {
                trace("[LED] Гасим невидимые квартиры > " + invisible.join(", "));
                esp.turnOffRoomsBatch(invisible, "instant", null, null, false);
            }
        }

        private function extractFloorNumber(apartmentId:String):int {
            if (!apartmentId || apartmentId.length == 0) return -1;
            var firstChar:String = apartmentId.charAt(0);
            var n:int = parseInt(firstChar);
            if (isNaN(n)) return -1;
            return n;
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
            trace("[LED] Reset - выключаем все светодиоды");
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
