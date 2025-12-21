package {
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.display.SimpleButton;
    import flash.display.DisplayObjectContainer;
    import flash.display.Bitmap;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.TransformGestureEvent;
    import flash.geom.Rectangle;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.text.TextField;

    /**
     * РџРѕР»РЅРѕСЌРєСЂР°РЅРЅС‹Р№ РїРѕРїР°Рї РґР»СЏ РїР»Р°РЅРёСЂРѕРІРѕРє.
     * РћРґРЅРѕ РёР·РѕР±СЂР°Р¶РµРЅРёРµ, РІРїРёСЃС‹РІР°РµС‚СЃСЏ РІ BaseImage, Р·Р°РєСЂС‹С‚РёРµ РїРѕ РєРЅРѕРїРєРµ.
     */
    public class PlanPopup extends MovieClip {
        private var absorber:Sprite;
        private var previousInputMode:String = null;
        public var BtnCloseImage:SimpleButton;
        public var BaseImage:MovieClip;
        public var tfPlanType:TextField;
        public var tfPlanArea:TextField;
        public var tfPlanRooms:TextField;
        public var tfPlanLivingArea:TextField;
        public var tfPlanBalkonArea:TextField;

        private var currentBitmap:Bitmap = null;
        private var currentApartmentId:String = "";

        public function PlanPopup() {
            super();
            previousInputMode = Multitouch.inputMode;
            Multitouch.inputMode = MultitouchInputMode.GESTURE;
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
            addEventListener(Event.REMOVED_FROM_STAGE, onRemoved);
        }

        public function showForApartment(apartmentId:String):void {
            currentApartmentId = apartmentId;
            clearBitmap();

            var type:String = CRMData.getDataById(apartmentId, "type");
            if (tfPlanType) {
                tfPlanType.text = (type && type != "0") ? type : "-";
            }
            var square:* = CRMData.getDataById(apartmentId, "square");
            if (tfPlanArea) {
                var sqNum:Number = Number(square);
                var sqText:String = (isNaN(sqNum) || sqNum == 0) ? "-" : Math.round(sqNum).toString() + " м²";
                tfPlanArea.text = sqText;
            }
            var roomsVal:* = CRMData.getDataById(apartmentId, "rooms");
            if (tfPlanRooms) {
                tfPlanRooms.text = formatRooms(roomsVal);
            }
            var living:* = CRMData.getDataById(apartmentId, "area_living");
            if (tfPlanLivingArea) {
                var livNum:Number = Number(living);
                var livText:String = (isNaN(livNum) || livNum == 0) ? "-" : Math.round(livNum).toString() + " м²";
                tfPlanLivingArea.text = livText;
            }
            var balcony:* = CRMData.getDataById(apartmentId, "area_balcony");
            if (tfPlanBalkonArea) {
                var balNum:Number = Number(balcony);
                var balText:String = (isNaN(balNum) || balNum == 0) ? "-" : Math.round(balNum).toString() + " м²";
                tfPlanBalkonArea.text = balText;
            }

            var raw:* = CRMData.getDataById(apartmentId, "plan");
            var url:String = null;
            if (raw is String) {
                url = raw as String;
            } else if (raw is Array && raw.length > 0) {
                url = String(raw[0]);
            }
            if (!url) return;

            var requested:String = currentApartmentId;
            ImageCache.getBitmap(url, function(bmp:Bitmap):void {
                if (!bmp || requested != currentApartmentId) return;
                placeIntoBase(bmp);
            }, function(err:String):void {
                trace("[PlanPopup] РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё РїР»Р°РЅР°: " + err);
            });
        }

        private function onAdded(e:Event):void {
            if (!stage) return;

            absorber = new Sprite();
            absorber.mouseEnabled = false;
            addChildAt(absorber, 0);

            stage.addEventListener(MouseEvent.MOUSE_WHEEL, absorb, true, int.MAX_VALUE, true);
            stage.addEventListener(TransformGestureEvent.GESTURE_ZOOM, absorb, true, int.MAX_VALUE, true);

            if (BtnCloseImage) {
                BtnCloseImage.addEventListener(MouseEvent.CLICK, onCloseClick);
            }
        }

        private function onRemoved(e:Event):void {
            cleanupListeners();
            clearBitmap();
            if (previousInputMode != null) {
                Multitouch.inputMode = previousInputMode;
            }
        }

        private function cleanupListeners():void {
            if (stage) {
                stage.removeEventListener(MouseEvent.MOUSE_WHEEL, absorb, true);
                stage.removeEventListener(TransformGestureEvent.GESTURE_ZOOM, absorb, true);
            }
            if (BtnCloseImage) {
                BtnCloseImage.removeEventListener(MouseEvent.CLICK, onCloseClick);
            }
        }

        private function absorb(e:Event):void {
            e.stopImmediatePropagation();
        }

        private function onCloseClick(e:MouseEvent):void {
            if (parent) {
                parent.removeChild(this);
            }
        }

        private function placeIntoBase(bmp:Bitmap):void {
            if (!bmp || !BaseImage) return;

            clearBitmap();

            var parentContainer:DisplayObjectContainer = BaseImage.parent as DisplayObjectContainer;
            if (!parentContainer) return;

            var bounds:Rectangle = BaseImage.getBounds(parentContainer);
            var origW:Number = bmp.bitmapData ? bmp.bitmapData.width : bmp.width;
            var origH:Number = bmp.bitmapData ? bmp.bitmapData.height : bmp.height;
            var scaleX:Number = bounds.width / origW;
            var scaleY:Number = bounds.height / origH;
            scaleX = isFinite(scaleX) ? scaleX : 1;
            scaleY = isFinite(scaleY) ? scaleY : 1;

            bmp.smoothing = true;
            bmp.scaleX = scaleX;
            bmp.scaleY = scaleY;
            bmp.x = bounds.x;
            bmp.y = bounds.y;

            parentContainer.addChild(bmp);
            currentBitmap = bmp;
        }

        private function clearBitmap():void {
            if (currentBitmap && currentBitmap.parent) {
                currentBitmap.parent.removeChild(currentBitmap);
            }
            currentBitmap = null;
        }

        private function formatRooms(val:*):String {
            var n:int = int(val);
            if (n <= 0) return "-";
            var suffix:String = "комнат";
            if (n == 1) suffix = "комната";
            else if (n >= 2 && n <= 4) suffix = "комнаты";
            else suffix = "комнат";
            return n.toString() + " " + suffix;
        }
    }
}



