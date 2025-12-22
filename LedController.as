package {
    public class LedController {

        private var esp:EspControl;

        public function LedController(espControl:EspControl) {
            this.esp = espControl;
        }

        //----------------------------------------------
        // ���� ��� HEX -> ������� � RGB Array ��� ESP
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
        // ���� �� ������� (��������� ������ ��� LedController)
        //----------------------------------------------
        private function getHexColorByStatus(status:String):String {
            switch(status) {
                case "Available": return "#00FF00";       // ������
                case "Reserved": return "#FFFF00";        // �����
                case "Occupied": return "#FF0000";        // �������
                case "Closed for sale": return "#FFFFFF"; // �����
                default: return "#000000";                 // ������
            }
        }

        //----------------------------------------------
        // ��������� ����� �������� �� �������
        //----------------------------------------------
        public function lightUpRoomByStatus(roomId:String):void {
            var status:String = CRMData.getDataById(roomId, "status");

            if(status == null) {
                return;
            }


            // ���������� ESP ������� ��������� ����� ��������
            esp.turnOnApartment(roomId, "pulse");
        }

        //----------------------------------------------
        // ��������� ����� �������� ���������� ������
        //----------------------------------------------
        public function lightUpRoom(roomId:String, color:String):void {

            var rgb:Array = hexToRGB(color);
            var brightness:* = CRMData.getDataById(roomId, "ledbrightness");
            var brightnessInt:int = (brightness !== null && brightness !== undefined && !isNaN(Number(brightness))) ? int(brightness) : -1;

            esp.turnOnApartmentWithColor(roomId, rgb, brightnessInt);
        }

        //----------------------------------------------
        // ������� ����� - ���������� floor_on
        //----------------------------------------------
        public function blinkFloorByStatus(floorId:int):void {
            var apartments:Object = CRMData.getAllData();

            if (!apartments) {
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
                return;
            }

            // ������� effect=blink, ��������� ��������� �� ���������
            esp.floorOn(floorId, null, 255, "blink3");
        }

        //----------------------------------------------
        // �������� ���� �� ��������
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
                return;
            }


            // API floor_on: ������� ����� ����� (zero-based), ��������� ��������� ���������
            esp.floorOn(floor);
        }

        //----------------------------------------------
        // �������� ��� ������� ������� (���������������) �������� ����� JSON
        //----------------------------------------------
        public function lightUpFilteredVisible():void {
            var buttons:Array = GlobalData.apartmentButtons;
            if (!buttons || buttons.length == 0) {
                return;
            }

            var ids:Array = [];
            for each (var btn:ApartmentButtonNew in buttons) {
                if (btn && btn.visible && btn.apartmentNumber) {
                    ids.push(btn.apartmentNumber);
                }
            }

            if (ids.length == 0) {
                // ���� ���� ������� ���, �� ����� ����� �������� ���������
            }

            // �������� ������ ��������� �������, ����� ��������� rooms_off ��� ������ all_off
            var apartments:Object = CRMData.getAllData();
            var invisible:Array = [];
            var visibleSet:Object = {};
            for each (var vid:String in ids) visibleSet[vid] = true;

            // ���������� ������� ���� (�� �������� ������, ����� �� ������ �������)
            var currentFloor:int = extractFloorNumber(GlobalData.activeButtonName);
            if (currentFloor < 0 && ids.length > 0) {
                currentFloor = extractFloorNumber(ids[0]);
            }

            for (var apt:String in apartments) {
                if (!visibleSet.hasOwnProperty(apt)) {
                    if (currentFloor >= 0) {
                        // �������������� ������ ������� ������
                        if (extractFloorNumber(apt) != currentFloor) continue;
                    }
                    invisible.push(apt);
                }
            }

                        // Формируем batch: rooms_on + rooms_off (только текущий этаж)
            var commands:Array = [];
            if (ids.length > 0) {
                var cmdOn:Object = esp.buildRoomsOnCommand(ids, "instant");
                if (cmdOn) commands.push(cmdOn);
            }
            if (invisible.length > 0) {
                var cmdOff:Object = esp.buildRoomsOffCommand(invisible, "instant");
                if (cmdOff) commands.push(cmdOff);
            }
            if (commands.length > 0) {
                esp.sendBatch(commands, null, null, false, false);
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
        // �������� ��� ����������� ������ (HEX)
        //----------------------------------------------
        public function lightUpAll(colorHex:String):void {
            var rgb:Array = hexToRGB(colorHex);


            esp.turnOnAll(rgb);
        }

        //----------------------------------------------
        // ��������� ���
        //----------------------------------------------
        public function resetLighting():void {
            esp.turnOffAll();
        }

        //----------------------------------------------
        // ���������������� ������ (���� ��������)
        //----------------------------------------------
        public function startRunningLights():void {
        }

        public function startFadeBlink():void {
        }

        public function startCycleRoomTypes():void {
        }

        public function startOccupancySimulation():void {
        }

        public function stopDemo():void {
            esp.disableDemoMode();
        }

        //----------------------------------------------
        // v4 demo mode (���������� ��� ������ �����)
        //----------------------------------------------
        public function startDemoMode():void {
            esp.enableDemoMode();
        }

        public function stopDemoMode():void {
            esp.disableDemoMode();
        }
    }
}
