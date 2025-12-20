package {
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.display.SimpleButton;
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.MovieClip;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.TransformGestureEvent;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.display.Bitmap;
    import flash.geom.Rectangle;
    import flash.text.TextField;

    /**
     * Простой полноэкранный попап-заглушка под фото.
     * Затемняет сцену и блокирует прокрутку/пинч под собой.
     */
    public class PhotoPopup extends MovieClip {
        // Фон/оверлей убран, чтобы показывать графику из символа.
        private var absorber:Sprite;
        public var BtnCloseImage:SimpleButton;
        public var BaseImage:MovieClip;
        public var btn_previous:SimpleButton;
        public var btn_next:SimpleButton;
        public var tfPhotoType:TextField;
        public var tfPhotoArea:TextField;
        private var loadedBitmaps:Array = [];
        private var activeBitmaps:Array = [];
        private var activeIndex:int = 0;
        private var currentActiveBitmap:Bitmap = null;
        private var activeSlots:Array = [];
        private var highlight:Sprite = null;
        private var currentApartmentId:String = "";

        public function PhotoPopup() {
            super();
            Multitouch.inputMode = MultitouchInputMode.GESTURE;
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
            addEventListener(Event.REMOVED_FROM_STAGE, onRemoved);
        }

        // Вызывается снаружи, сейчас ничего не делает кроме гарантии создания попапа
        public function showForApartment(apartmentId:String):void {
            currentApartmentId = apartmentId;
            clearLoadedBitmaps();
            clearActive();
            activeSlots = [];

            var type:String = CRMData.getDataById(apartmentId, "type");
            if (tfPhotoType) {
                tfPhotoType.text = type ? type : "";
            }
            var square:* = CRMData.getDataById(apartmentId, "square");
            if (tfPhotoArea) {
                var sqNum:Number = Number(square);
                var sqText:String = Math.round(sqNum).toString() + " м²";
                tfPhotoArea.text = sqText;
            }

            var raw:* = CRMData.getDataById(apartmentId, "render");
            var urls:Array = [];
            if (raw is String) {
                urls = [raw];
            } else if (raw is Array) {
                urls = raw;
            }

            var maxSlots:int = 5;
            for (var i:int = 0; i < maxSlots; i++) {
                if (i < urls.length) {
                    loadIntoSlot(i, String(urls[i]));
                }
            }
            activeIndex = 0;
        }

        private function onAdded(e:Event):void {
            if (!stage) return;

            // Чтобы перехватывать колесо/пинч, но не рисовать оверлей
            absorber = new Sprite();
            absorber.mouseEnabled = false;
            addChildAt(absorber, 0);

            stage.addEventListener(MouseEvent.MOUSE_WHEEL, absorb, true, int.MAX_VALUE, true);
            stage.addEventListener(TransformGestureEvent.GESTURE_ZOOM, absorb, true, int.MAX_VALUE, true);

            if (BtnCloseImage) {
                BtnCloseImage.addEventListener(MouseEvent.CLICK, onCloseClick);
            }
            if (btn_previous) {
                btn_previous.addEventListener(MouseEvent.CLICK, onPrev);
            }
            if (btn_next) {
                btn_next.addEventListener(MouseEvent.CLICK, onNext);
            }
        }

        private function onRemoved(e:Event):void {
            cleanupListeners();
            if (!hasEventListener(Event.ADDED_TO_STAGE)) {
                addEventListener(Event.ADDED_TO_STAGE, onAdded);
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
            if (btn_previous) {
                btn_previous.removeEventListener(MouseEvent.CLICK, onPrev);
            }
            if (btn_next) {
                btn_next.removeEventListener(MouseEvent.CLICK, onNext);
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

        private function loadIntoSlot(index:int, url:String):void {
            var slotName:String = "topImage_0" + index;
            var slot:DisplayObject = this.hasOwnProperty(slotName) ? this[slotName] as DisplayObject : getChildByName(slotName);
            if (!slot) return;
            activeSlots[index] = slot;

            var requestedApt:String = currentApartmentId;
            ImageCache.getBitmap(url, function(bmp:Bitmap):void {
                if (!bmp || requestedApt != currentApartmentId) return;
                placeBitmapIntoSlot(slot, bmp);
                addActiveBitmap(bmp);
            }, function(err:String):void {
                trace("[PhotoPopup] Ошибка загрузки " + url + ": " + err);
            });
        }

        private function placeBitmapIntoSlot(slot:DisplayObject, bmp:Bitmap):void {
            if (!bmp) return;
            bmp.smoothing = true;

            var slotContainer:DisplayObjectContainer = slot as DisplayObjectContainer;
            var parentContainer:DisplayObjectContainer = slotContainer ? slotContainer : (slot.parent ? slot.parent as DisplayObjectContainer : this);
            if (!parentContainer) return;

            var bounds:Rectangle = slot.getBounds(parentContainer);
            var origW:Number = bmp.bitmapData ? bmp.bitmapData.width : bmp.width;
            var origH:Number = bmp.bitmapData ? bmp.bitmapData.height : bmp.height;
            var scaleX:Number = bounds.width / origW;
            var scaleY:Number = bounds.height / origH;
            scaleX = isFinite(scaleX) ? scaleX : 1;
            scaleY = isFinite(scaleY) ? scaleY : 1;
            bmp.scaleX = scaleX;
            bmp.scaleY = scaleY;

            bmp.x = bounds.x;
            bmp.y = bounds.y;

            parentContainer.addChild(bmp);
            loadedBitmaps.push(bmp);
        }

        private function clearLoadedBitmaps():void {
            for each (var b:Bitmap in loadedBitmaps) {
                if (b && b.parent) b.parent.removeChild(b);
            }
            loadedBitmaps = [];
        }

        private function addActiveBitmap(source:Bitmap):void {
            var clone:Bitmap = new Bitmap(source.bitmapData);
            clone.smoothing = true;
            activeBitmaps.push(clone);
            if (activeBitmaps.length == 1) {
                showActiveAt(0);
            }
        }

        private function showActiveAt(index:int):void {
            if (!BaseImage) return;
            if (index < 0 || index >= activeBitmaps.length) return;
            activeIndex = index;

            var bmp:Bitmap = activeBitmaps[index];
            var parentContainer:DisplayObjectContainer = BaseImage.parent as DisplayObjectContainer;
            if (!parentContainer) return;

            if (currentActiveBitmap && currentActiveBitmap.parent) {
                currentActiveBitmap.parent.removeChild(currentActiveBitmap);
            }

            var bounds:Rectangle = BaseImage.getBounds(parentContainer);
            var origW:Number = bmp.bitmapData ? bmp.bitmapData.width : bmp.width;
            var origH:Number = bmp.bitmapData ? bmp.bitmapData.height : bmp.height;
            var scaleX:Number = bounds.width / origW;
            var scaleY:Number = bounds.height / origH;
            scaleX = isFinite(scaleX) ? scaleX : 1;
            scaleY = isFinite(scaleY) ? scaleY : 1;

            bmp.scaleX = scaleX;
            bmp.scaleY = scaleY;
            bmp.x = bounds.x;
            bmp.y = bounds.y;

            parentContainer.addChild(bmp);
            currentActiveBitmap = bmp;

            var slotForActive:DisplayObject = (activeSlots && activeSlots.length > index) ? activeSlots[index] as DisplayObject : null;
            if (slotForActive && slotForActive.parent) {
                updateHighlight(slotForActive);
            } else {
                removeHighlight();
            }
        }

        private function onPrev(e:MouseEvent):void {
            e.stopImmediatePropagation();
            if (activeBitmaps.length == 0) return;
            if (activeIndex <= 0) return;
            var nextIndex:int = activeIndex - 1;
            showActiveAt(nextIndex);
        }

        private function onNext(e:MouseEvent):void {
            e.stopImmediatePropagation();
            if (activeBitmaps.length == 0) return;
            if (activeIndex >= activeBitmaps.length - 1) return;
            var nextIndex:int = activeIndex + 1;
            showActiveAt(nextIndex);
        }

        private function clearActive():void {
            if (currentActiveBitmap && currentActiveBitmap.parent) {
                currentActiveBitmap.parent.removeChild(currentActiveBitmap);
            }
            currentActiveBitmap = null;
            activeBitmaps = [];
            activeIndex = 0;
            removeHighlight();
        }

        private function updateHighlight(slot:DisplayObject):void {
            var parentContainer:DisplayObjectContainer = slot.parent as DisplayObjectContainer;
            if (!parentContainer) return;
            if (!highlight) {
                highlight = new Sprite();
                highlight.mouseEnabled = false;
                highlight.mouseChildren = false;
            }
            var bounds:Rectangle = slot.getBounds(parentContainer);
            highlight.graphics.clear();
            highlight.graphics.lineStyle(4, 0xE78834, 1);
            highlight.graphics.drawRect(bounds.x, bounds.y, bounds.width, bounds.height);
            highlight.graphics.endFill();
            if (!highlight.parent) {
                parentContainer.addChild(highlight);
            } else if (highlight.parent != parentContainer) {
                highlight.parent.removeChild(highlight);
                parentContainer.addChild(highlight);
            }
            parentContainer.setChildIndex(highlight, parentContainer.numChildren - 1);
        }

        private function removeHighlight():void {
            if (highlight && highlight.parent) {
                highlight.parent.removeChild(highlight);
            }
        }
    }
}
