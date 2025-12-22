package {
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.events.MouseEvent;
    import flash.geom.ColorTransform;
    import flash.events.Event;
    import flash.display.DisplayObjectContainer;
    import CRMData;
    import LedController;

    public class ApartmentButtonNew extends Sprite {

        public var apartmentNumber:String = "";

        private var pulseDirection:int = -1;
        private var pulseActive:Boolean = false;
        private var pulseMinAlpha:Number = 0.5;
        private var pulseMaxAlpha:Number = 1.0;
        private var pulseSpeed:Number = 0.03;
        private var esp:EspControl = new EspControl(AppConfig.getEspUrl());
        private var led:LedController = new LedController(esp);

        

        private var polygonShape:Sprite;
        private var labelField:TextField;
        private var labelBg:Sprite;

        private var polyPoints:Array = null; // координаты многоугольника
        private var lastSelectedFloor:int = -1;

        public function ApartmentButtonNew() {
            super();

            polygonShape = new Sprite();
            addChild(polygonShape);

            labelBg = new Sprite();
            addChild(labelBg);

            labelField = new TextField();
            labelField.mouseEnabled = false;
            labelField.selectable = false;
            labelBg.addChild(labelField);

            // Отключаем hitTest для формы и label, чтобы не блокировать движение карты
            polygonShape.mouseEnabled = false;
            polygonShape.mouseChildren = false;
            labelBg.mouseEnabled = false;
            labelBg.mouseChildren = false;

            // Кликается только сам контейнер-кнопка
            this.mouseChildren = true;
            this.mouseEnabled = true;


            // Устанавливаем цвет статуса (выделено в отдельную функцию)
            setColorByStatus();

            // Один-единственный обработчик клика
            this.addEventListener(MouseEvent.CLICK, onClickWrapper);
        }

        // Новая функция для установки цвета по статусу из CRMData
        public function setColorByStatus():void {
            try {
                var status:String = CRMData.getDataById(apartmentNumber, "status");
                if (status) {
                    var ct:ColorTransform = new ColorTransform();

                    switch(status) {
                        case "Available":
                            ct.color = 0x00CC00; // зеленый
                            break;

                        case "Reserved":
                            ct.color = 0xFFCC00; // желтый
                            break;

                        case "Occupied":
                            ct.color = 0xCC0000; // красный
                            break;

                        case "Сlosed for sale":
                            ct.color = 0x999999; // серый
                            break;

                        default:
                            ct.color = 0x999999; // на всякий случай
                            break;
                    }

                    polygonShape.transform.colorTransform = ct;
                }

            } catch (e:Error) {
            }
        }

        public function setShape(points:Array):void {
            polyPoints = points;

            polygonShape.graphics.clear();
            polygonShape.graphics.lineStyle(2, 0x000000);
            polygonShape.graphics.beginFill(0xFFCC00, 0.5);

            polygonShape.graphics.moveTo(points[0][0], points[0][1]);
            for (var i:int = 1; i < points.length; i++) {
                polygonShape.graphics.lineTo(points[i][0], points[i][1]);
            }
            polygonShape.graphics.lineTo(points[0][0], points[0][1]);
            polygonShape.graphics.endFill();

            updateLabelPosition(points);
        }

        private function updateLabelPosition(points:Array):void {
            var cx:Number = 0;
            var cy:Number = 0;

            for each (var pt:Array in points) {
                cx += pt[0];
                cy += pt[1];
            }
            cx /= points.length;
            cy /= points.length;

            labelField.text = apartmentNumber;

            // Чёрный текст
            var fmt:TextFormat = new TextFormat("Arial", 10, 0x000000, true);
            labelField.setTextFormat(fmt);
            labelField.defaultTextFormat = fmt;
            labelField.width = labelField.textWidth + 10;
            labelField.height = labelField.textHeight + 4;

            // Белый фон под текстом
            labelBg.graphics.clear();
            labelBg.graphics.beginFill(0xFFFFFF, 1); // белый, непрозрачный
            labelBg.graphics.drawRect(0, 0, labelField.width, labelField.height);
            labelBg.graphics.endFill();

            labelBg.x = cx - labelField.width / 2;
            labelBg.y = cy - labelField.height / 2;
            labelField.x = 5;
            labelField.y = 2;
        }

        // --------------------------------------------------------------------
        // Проверка попадания курсора внутрь многоугольника
        // --------------------------------------------------------------------

        private function onClickWrapper(e:MouseEvent):void {
            if (isCursorInsidePolygon())
                onRealClick();
        }

        private function isCursorInsidePolygon():Boolean {
            if (!polyPoints || polyPoints.length < 3) return false;

            var x:Number = mouseX;
            var y:Number = mouseY;

            var inside:Boolean = false;
            var j:int = polyPoints.length - 1;

            for (var i:int = 0; i < polyPoints.length; i++) {
                var xi:Number = polyPoints[i][0];
                var yi:Number = polyPoints[i][1];
                var xj:Number = polyPoints[j][0];
                var yj:Number = polyPoints[j][1];

                var intersect:Boolean =
                    ((yi > y) != (yj > y)) &&
                    (x < (xj - xi) * (y - yi) / (yj - yi) + xi);

                if (intersect) inside = !inside;
                j = i;
            }

            return inside;
        }

        // --------------------------------------------------------------------
        // Твой оригинальный обработчик клика
        // --------------------------------------------------------------------

        private function onRealClick():void {

            if (!apartmentNumber) return;

            // Найдем существующий ApartmentPopup на сцене (если есть)
            var popup:ApartmentPopup = null;
            if (stage) {
                for (var i:int = 0; i < stage.numChildren; i++) {
                    var child:* = stage.getChildAt(i);
                    if (child is ApartmentPopup) {
                        popup = child as ApartmentPopup;
                        break;
                    }
                }
            }

            if (GlobalData.activeButton && GlobalData.activeButton != this)
                GlobalData.activeButton.stopPulse();

            this.startPulse();
            GlobalData.activeButton = this;
            GlobalData.activeButtonName = apartmentNumber;  // <-- Сохраняем имя кнопки отдельно!

            led.lightUpRoomByStatus(apartmentNumber);
            lastSelectedFloor = extractFloorNumber(apartmentNumber);


            if (popup) {
                ensurePopupListener(popup);
                if (popup.getCurrentApartmentNumber() == apartmentNumber)
                    return;

                popup.showApartmentInfo(apartmentNumber);
            } else {
                if (stage) {
                    popup = new ApartmentPopup();
                    stage.addChild(popup);
                    popup.x = (stage.stageWidth - popup.width) / 2;
                    popup.y = (stage.stageHeight - popup.height) / 2;
                    GlobalData.popup = popup;

                    ensurePopupListener(popup);
                    popup.showApartmentInfo(apartmentNumber);
                } else {
                }
            }
        }


        // --------------------------------------------------------------------
        // Pulse Animation
        // --------------------------------------------------------------------

        public function startPulse():void {
            if (!pulseActive) {
                pulseActive = true;
                this.addEventListener(Event.ENTER_FRAME, onPulseFrame);
            }
        }

        public function stopPulse():void {
            if (pulseActive) {
                pulseActive = false;
                this.removeEventListener(Event.ENTER_FRAME, onPulseFrame);
                this.alpha = 1.0;
            }
        }

        private function onPulseFrame(e:Event):void {
            this.alpha += pulseSpeed * pulseDirection;
            if (this.alpha <= pulseMinAlpha) {
                this.alpha = pulseMinAlpha;
                pulseDirection = 1;
            } else if (this.alpha >= pulseMaxAlpha) {
                this.alpha = pulseMaxAlpha;
                pulseDirection = -1;
            }
        }

        // --------------------------------------------------------------------
        // Popup handling
        // --------------------------------------------------------------------

        private function ensurePopupListener(popup:ApartmentPopup):void {
            if (!popup.hasEventListener(ApartmentPopup.CLOSED)) {
                popup.addEventListener(ApartmentPopup.CLOSED, onPopupClosed, false, 0, true);
            }
        }

        private function onPopupClosed(e:Event):void {
            led.lightUpFilteredVisible();
        }

        private function extractFloorNumber(apartmentId:String):int {
            if (!apartmentId || apartmentId.length == 0) return -1;
            // В ID квартиры первым символом идёт этаж (у нас этажи 2-8), остальное — номер
            var firstChar:String = apartmentId.charAt(0);
            var n:int = parseInt(firstChar);
            if (isNaN(n)) {
                return -1;
            }
            return n;
        }
    }
}
